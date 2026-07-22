Set-StrictMode -Version 2.0

function Get-AriaCapabilityMapFromBytecode { param($Bytecode) $map=@{};foreach($cap in @($Bytecode.capabilities)){$map[[string]$cap.name]=$cap};return $map }
function Assert-AriaRuntimeEffect { param($Policy,[string]$Effect,[string]$Scope='.') $decision=Test-AriaPolicyAllowsEffect $Policy $Effect $Scope;if(-not$decision.allowed){throw "ARIA VM denied effect '$Effect': $($decision.reason)"} }
function Get-AriaRuntimeValueType { param($Value) if($null-eq$Value){return 'Null'};if($Value-is[bool]){return 'Bool'};if($Value-is[string]){return 'Text'};if($Value-is[byte]-or$Value-is[sbyte]-or$Value-is[int16]-or$Value-is[uint16]-or$Value-is[int32]-or$Value-is[uint32]-or$Value-is[int64]-or$Value-is[uint64]-or$Value-is[single]-or$Value-is[double]-or$Value-is[decimal]){return 'Number'};return 'Any' }
function Assert-AriaRuntimeType { param([string]$Expected,$Value,[string]$Context) $actual=Get-AriaRuntimeValueType $Value;if(-not(Test-AriaTypeAssignable $Expected $actual)){throw "ARIA VM type error in ${Context}: expected $Expected, received $actual."} }
function Copy-AriaRuntimeTable { param([hashtable]$Table) $copy=@{};foreach($key in $Table.Keys){$copy[$key]=$Table[$key]};return $copy }
function New-AriaScopeStack { $scopes=New-Object Collections.ArrayList;$null=$scopes.Add(@{});return,$scopes }
function Get-AriaScopedValue { param($Scopes,[string]$Name) for($i=$Scopes.Count-1;$i-ge0;$i--){if($Scopes[$i].ContainsKey($Name)){return [pscustomobject]@{found=$true;value=$Scopes[$i][$Name]}}};return [pscustomobject]@{found=$false;value=$null} }
function Set-AriaScopedValue { param($Scopes,[string]$Name,$Value) for($i=$Scopes.Count-1;$i-ge0;$i--){if($Scopes[$i].ContainsKey($Name)){$Scopes[$i][$Name]=$Value;return}};throw "ARIA VM cannot set undefined variable '$Name'." }
function Add-AriaScope { param($Scopes,[hashtable]$Values=@{}) $null=$Scopes.Add($Values) }
function Remove-AriaScope { param($Scopes) if($Scopes.Count-le1){throw 'ARIA VM cannot remove the root scope.'};$Scopes.RemoveAt($Scopes.Count-1) }
function Pop-AriaRuntime { param($Stack,[string]$Context) if($Stack.Count-eq0){throw "ARIA VM stack underflow at $Context."};return $Stack.Pop() }

function Resolve-AriaRuntimePathForEffect {
    param([hashtable]$Active,[hashtable]$CapabilityMap,$Policy,[string]$Effect,[string]$WorkspaceRoot,[string]$RequestedPath)
    [string[]]$names=@($Active.Keys|ForEach-Object{[string]$_});[Array]::Sort($names,[StringComparer]::Ordinal);$authorized=New-Object System.Collections.Generic.List[object]
    foreach($name in $names){if(-not$CapabilityMap.ContainsKey($name)){continue};$cap=$CapabilityMap[$name];if([string]$cap.effect-ne$Effect){continue};$decision=Test-AriaPolicyAllowsCapability $Policy $cap;if(-not$decision.allowed){continue};try{$resolved=Resolve-AriaConfinedPath $WorkspaceRoot ([string]$cap.scope) $RequestedPath;$scope=([string]$cap.scope).Replace([char]92,[char]47).TrimEnd([char]47);$authorized.Add([pscustomobject]@{name=$name;score=$scope.Length;path=$resolved})}catch{continue}}
    if($authorized.Count-eq0){throw "ARIA VM has no active '$Effect' capability authorizing path '$RequestedPath'."};$best=$authorized[0];foreach($candidate in $authorized){if($candidate.score-gt$best.score-or($candidate.score-eq$best.score-and[string]::CompareOrdinal([string]$candidate.name,[string]$best.name)-lt0)){$best=$candidate}};return $best
}
function Assert-AriaTextEffectLimit { param($Policy,[string]$Effect,[AllowEmptyString()][string]$Text,[int64]$Default) $limit=Get-AriaPolicyMaxBytes $Policy $Effect $Default;$encoding=New-Object Text.UTF8Encoding($false);if([int64]$encoding.GetByteCount($Text)-gt$limit){throw "ARIA $Effect payload exceeds policy maxBytes ($limit)."} }
function Assert-AriaFileReadLimit { param($Policy,[string]$Path) $item=Get-Item -LiteralPath $Path -Force;if($item.PSIsContainer){throw "ARIA fs.read target is a directory: $Path"};$limit=Get-AriaPolicyMaxBytes $Policy 'fs.read' 4194304;if([int64]$item.Length-gt$limit){throw "ARIA fs.read target exceeds policy maxBytes ($limit): $Path"} }
function Assert-AriaFileWriteLimit { param($Policy,[string]$Text) Assert-AriaTextEffectLimit $Policy 'fs.write' $Text 1048576 }
function Save-AriaMemoryState { param([string]$Path,[hashtable]$Memories,$Policy) $ordered=[ordered]@{};foreach($memoryName in @($Memories.Keys|Sort-Object)){$entries=[ordered]@{};foreach($key in @($Memories[$memoryName].Keys|Sort-Object)){$entries[$key]=$Memories[$memoryName][$key]};$ordered[$memoryName]=[pscustomobject]$entries};$serialized=([pscustomobject]$ordered|ConvertTo-Json -Depth 50)+[Environment]::NewLine;Assert-AriaTextEffectLimit $Policy 'memory.write' $serialized 16777216;$temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp';try{Write-AriaUtf8NoBom $temp $serialized;Move-Item -LiteralPath $temp -Destination $Path -Force}finally{Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue} }

function Invoke-AriaBinaryRuntime {
    param([string]$Opcode, $Left, $Right, [int]$Line)

    switch ($Opcode) {
        'ADD' {
            if ($Left -is [string] -and $Right -is [string]) { return ([string]$Left + [string]$Right) }
            Assert-AriaRuntimeType 'Number' $Left "ADD line $Line"
            Assert-AriaRuntimeType 'Number' $Right "ADD line $Line"
            return ($Left + $Right)
        }
        'SUB' { Assert-AriaRuntimeType 'Number' $Left "SUB line $Line"; Assert-AriaRuntimeType 'Number' $Right "SUB line $Line"; return ($Left - $Right) }
        'MUL' { Assert-AriaRuntimeType 'Number' $Left "MUL line $Line"; Assert-AriaRuntimeType 'Number' $Right "MUL line $Line"; return ($Left * $Right) }
        'DIV' {
            Assert-AriaRuntimeType 'Number' $Left "DIV line $Line"
            Assert-AriaRuntimeType 'Number' $Right "DIV line $Line"
            if ([double]$Right -eq 0) { throw "ARIA division by zero at source line $Line." }
            return ([double]$Left / [double]$Right)
        }
        'EQ' { return ((ConvertTo-AriaJson ([pscustomobject]@{ v = $Left })) -eq (ConvertTo-AriaJson ([pscustomobject]@{ v = $Right }))) }
        'NE' { return ((ConvertTo-AriaJson ([pscustomobject]@{ v = $Left })) -ne (ConvertTo-AriaJson ([pscustomobject]@{ v = $Right }))) }
        'LT' { Assert-AriaRuntimeType 'Number' $Left "LT line $Line"; Assert-AriaRuntimeType 'Number' $Right "LT line $Line"; return ([double]$Left -lt [double]$Right) }
        'LE' { Assert-AriaRuntimeType 'Number' $Left "LE line $Line"; Assert-AriaRuntimeType 'Number' $Right "LE line $Line"; return ([double]$Left -le [double]$Right) }
        'GT' { Assert-AriaRuntimeType 'Number' $Left "GT line $Line"; Assert-AriaRuntimeType 'Number' $Right "GT line $Line"; return ([double]$Left -gt [double]$Right) }
        'GE' { Assert-AriaRuntimeType 'Number' $Left "GE line $Line"; Assert-AriaRuntimeType 'Number' $Right "GE line $Line"; return ([double]$Left -ge [double]$Right) }
        'AND' { Assert-AriaRuntimeType 'Bool' $Left "AND line $Line"; Assert-AriaRuntimeType 'Bool' $Right "AND line $Line"; return ([bool]$Left -and [bool]$Right) }
        'OR' { Assert-AriaRuntimeType 'Bool' $Left "OR line $Line"; Assert-AriaRuntimeType 'Bool' $Right "OR line $Line"; return ([bool]$Left -or [bool]$Right) }
        default { throw "ARIA VM unknown binary opcode '$Opcode'." }
    }
}

function Invoke-AriaInstructionSequence {
    param([object[]]$Instructions,$Context,$Scopes,[hashtable]$ActiveCapabilities,[int]$CallDepth=0)
    if($CallDepth-gt64){throw 'ARIA VM call depth exceeded 64.'};$stack=New-Object Collections.Stack
    for($ip=0;$ip-lt$Instructions.Count;$ip++){
        $ins=$Instructions[$ip];$op=[string]$ins.op
        switch($op){
            'PUSH_CONST'{$stack.Push($Context.bytecode.constants[[int]$ins.arg])}
            'LOAD'{$result=Get-AriaScopedValue $Scopes ([string]$ins.arg);if(-not$result.found){throw "ARIA VM unknown variable '$($ins.arg)' at source line $($ins.line)."};$stack.Push($result.value)}
            'STORE'{$value=Pop-AriaRuntime $stack "STORE line $($ins.line)";Assert-AriaRuntimeType ([string]$ins.type) $value "variable $($ins.arg)";$Scopes[$Scopes.Count-1][[string]$ins.arg]=$value}
            'SET'{$value=Pop-AriaRuntime $stack "SET line $($ins.line)";Set-AriaScopedValue $Scopes ([string]$ins.arg) $value}
            {$_-in@('ADD','SUB','MUL','DIV','EQ','NE','LT','LE','GT','GE','AND','OR')}{$right=Pop-AriaRuntime $stack "$op line $($ins.line)";$left=Pop-AriaRuntime $stack "$op line $($ins.line)";$stack.Push((Invoke-AriaBinaryRuntime $op $left $right ([int]$ins.line)))}
            'NOT'{$value=Pop-AriaRuntime $stack "NOT line $($ins.line)";Assert-AriaRuntimeType 'Bool' $value "NOT line $($ins.line)";$stack.Push(-not[bool]$value)}
            'NEG'{$value=Pop-AriaRuntime $stack "NEG line $($ins.line)";Assert-AriaRuntimeType 'Number' $value "NEG line $($ins.line)";$stack.Push(-$value)}
            'EMIT'{Assert-AriaRuntimeEffect $Context.policy 'console.emit';$text=[string](Pop-AriaRuntime $stack "EMIT line $($ins.line)");Assert-AriaTextEffectLimit $Context.policy 'console.emit' $text 262144;$Context.outputs.Add($text);if(-not$Context.passThru){if(Get-Command Write-AriaStream -ErrorAction SilentlyContinue){Write-AriaStream $text}else{Write-Host "∿ $text"}}}
            'SIGNAL'{Assert-AriaRuntimeEffect $Context.policy 'console.emit';$text=[string](Pop-AriaRuntime $stack "SIGNAL line $($ins.line)");Assert-AriaTextEffectLimit $Context.policy 'console.emit' $text 262144;$state=[string]$ins.state;$Context.events.Add([pscustomobject][ordered]@{kind='signal';state=$state;text=$text;line=[int]$ins.line});if(-not$Context.passThru){$render=switch($state){'pulse'{'Pulse'}'pass'{'Pass'}'warn'{'Warn'}'fail'{'Fail'}default{'Info'}};if(Get-Command Write-AriaTreeStage -ErrorAction SilentlyContinue){Write-AriaTreeStage -Name $text -State $render -Depth 1}}}
            'MEM_SET'{Assert-AriaRuntimeEffect $Context.policy 'memory.write';$value=Pop-AriaRuntime $stack "MEM_SET line $($ins.line)";$expected=[string]$Context.memoryTypes[[string]$ins.memory][[string]$ins.key];Assert-AriaRuntimeType $expected $value "memory $($ins.memory).$($ins.key)";$Context.memories[[string]$ins.memory][[string]$ins.key]=$value;$Context.memoryDirty=$true}
            'MEM_GET'{Assert-AriaRuntimeEffect $Context.policy 'memory.read';if(-not$Context.memories.ContainsKey([string]$ins.memory)-or-not$Context.memories[[string]$ins.memory].ContainsKey([string]$ins.key)){throw "ARIA VM missing memory '$($ins.memory).$($ins.key)'."};$stack.Push($Context.memories[[string]$ins.memory][[string]$ins.key])}
            'REQUIRE_CAP'{$name=[string]$ins.arg;if(-not$Context.capabilityMap.ContainsKey($name)){throw "ARIA VM unknown capability '$name'."};$decision=Test-AriaPolicyAllowsCapability $Context.policy $Context.capabilityMap[$name];if(-not$decision.allowed){throw "ARIA VM denied capability '$name': $($decision.reason)"};$ActiveCapabilities[$name]=$true}
            'ASSERT_TRUE'{$value=Pop-AriaRuntime $stack "ASSERT_TRUE line $($ins.line)";Assert-AriaRuntimeType 'Bool' $value "assert line $($ins.line)";if(-not[bool]$value){throw "ARIA assertion failed at source line $($ins.line)."}}
            'FS_READ'{$path=[string](Pop-AriaRuntime $stack "FS_READ line $($ins.line)");$auth=Resolve-AriaRuntimePathForEffect $ActiveCapabilities $Context.capabilityMap $Context.policy 'fs.read' $Context.workspaceRoot $path;Assert-AriaFileReadLimit $Context.policy $auth.path;$Scopes[$Scopes.Count-1][[string]$ins.arg]=Read-AriaUtf8Text $auth.path}
            'FS_WRITE'{$value=[string](Pop-AriaRuntime $stack "FS_WRITE line $($ins.line)");$path=[string](Pop-AriaRuntime $stack "FS_WRITE line $($ins.line)");$auth=Resolve-AriaRuntimePathForEffect $ActiveCapabilities $Context.capabilityMap $Context.policy 'fs.write' $Context.workspaceRoot $path;Assert-AriaFileWriteLimit $Context.policy $value;Write-AriaUtf8NoBom $auth.path $value}
            'AGENT_DISPATCH'{Assert-AriaRuntimeEffect $Context.policy 'agent.dispatch';$agent=[string]$ins.agent;if(-not$Context.agentMap.ContainsKey($agent)){throw "ARIA VM unknown agent '$agent'."};$task=[string](Pop-AriaRuntime $stack "AGENT_DISPATCH line $($ins.line)");$Context.events.Add([pscustomobject][ordered]@{kind='agent';state='pulse';agent=$agent;text=$task;line=[int]$ins.line});if(-not$Context.passThru-and(Get-Command Write-AriaTreeStage -ErrorAction SilentlyContinue)){Write-AriaTreeStage -Name ("agent {0}"-f$agent) -State Pulse -Detail $task -Depth 1}}
            'CALL'{$name=[string]$ins.name;if(-not $Context.functionMap.ContainsKey($name)){throw "ARIA VM unknown function '$name'."};$fn=$Context.functionMap[$name];$argCount=[int]$ins.argCount;if($argCount-eq0){[object[]]$args=@()}else{[object[]]$args=New-Object object[] $argCount};for($a=$args.Length-1;$a-ge0;$a--){$args[$a]=Pop-AriaRuntime $stack "CALL $name line $($ins.line)"};$fnScopes=New-AriaScopeStack;for($a=0;$a-lt$args.Length;$a++){$param=$fn.parameters[$a];Assert-AriaRuntimeType ([string]$param.type) $args[$a] "argument $($a+1) to $name";$fnScopes[0][[string]$param.name]=$args[$a]};$result=Invoke-AriaInstructionSequence @($fn.instructions) $Context $fnScopes @{} ($CallDepth+1);if($result.control-ne'return'){throw "ARIA function '$name' terminated without return."};Assert-AriaRuntimeType ([string]$fn.returnType) $result.value "return from $name";$stack.Push($result.value)}
            'IF'{$condition=Pop-AriaRuntime $stack "IF line $($ins.line)";Assert-AriaRuntimeType 'Bool' $condition "if line $($ins.line)";Add-AriaScope $Scopes;try{$branch=if([bool]$condition){@($ins.then)}else{@($ins.else)};$result=Invoke-AriaInstructionSequence $branch $Context $Scopes (Copy-AriaRuntimeTable $ActiveCapabilities) $CallDepth}finally{Remove-AriaScope $Scopes};if($result.control-ne'normal'){return $result}}
            'REPEAT'{$raw=Pop-AriaRuntime $stack "REPEAT line $($ins.line)";Assert-AriaRuntimeType 'Number' $raw "repeat line $($ins.line)";$count=[double]$raw;if($count-lt0-or$count-gt[int]$ins.max-or[math]::Floor($count)-ne$count){throw "ARIA repeat count must be an integer from 0 through $($ins.max) at source line $($ins.line)."};for($iteration=0;$iteration-lt[int]$count;$iteration++){Add-AriaScope $Scopes @{([string]$ins.iterator)=[long]$iteration};try{$result=Invoke-AriaInstructionSequence @($ins.body) $Context $Scopes (Copy-AriaRuntimeTable $ActiveCapabilities) $CallDepth}finally{Remove-AriaScope $Scopes};if($result.control-ne'normal'){return $result}}}
            'RETURN'{$value=if([bool]$ins.hasValue){Pop-AriaRuntime $stack "RETURN line $($ins.line)"}else{$null};if($stack.Count-ne0){throw "ARIA VM function return left $($stack.Count) operand(s) on the stack."};return [pscustomobject]@{control='return';value=$value}}
            'HALT'{if($stack.Count-ne0){throw "ARIA VM halt left $($stack.Count) operand(s) on the stack."};return [pscustomobject]@{control='halt';value=$null}}
            default{throw "ARIA VM unknown opcode '$op' at instruction $ip."}
        }
    }
    if($stack.Count-ne0){throw "ARIA VM sequence terminated with a non-empty operand stack ($($stack.Count))."};return [pscustomobject]@{control='normal';value=$null}
}

function Invoke-AriaContainer {
    param($Container,[string]$PolicyPath,[string]$WorkspaceRoot=(Get-AriaRepositoryRoot),[switch]$PassThru)
    if(-not(Test-Path -LiteralPath $WorkspaceRoot -PathType Container)){throw "ARIA VM workspace does not exist: $WorkspaceRoot"};$WorkspaceRoot=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $WorkspaceRoot).Path);$bytecode=$Container.bytecode;$verification=Test-AriaBytecodeModel $bytecode;if(-not$verification.valid){throw('ARIA VM rejected unverified bytecode: '+($verification.errors-join'; '))};$policy=Get-AriaPolicy $PolicyPath;$validation=Test-AriaPolicyDocument $policy;if(-not$validation.valid){throw('ARIA VM requires a valid deny-by-default policy: '+($validation.errors-join'; '))}
    $capabilityMap=Get-AriaCapabilityMapFromBytecode $bytecode;$agentMap=@{};foreach($agent in @($bytecode.agents)){$agentMap[[string]$agent.name]=$agent};$functionMap=@{};foreach($fn in @($bytecode.functions)){$functionMap[[string]$fn.name]=$fn};$outputs=New-Object System.Collections.Generic.List[string];$events=New-Object System.Collections.Generic.List[object];$memories=@{};$memoryTypes=@{}
    foreach($memory in @($bytecode.memories)){$memories[[string]$memory.name]=ConvertTo-AriaHashtable $memory.values;$types=@{};foreach($property in $memory.types.PSObject.Properties){$types[$property.Name]=[string]$property.Value};$memoryTypes[[string]$memory.name]=$types}
    $stateRelative='.aria/state/'+$bytecode.programName+'.memory.json';$statePath=Resolve-AriaConfinedPath $WorkspaceRoot '.' $stateRelative;$stateRoot=Split-Path -Parent $statePath
    if(Test-Path -LiteralPath $statePath){$info=Get-Item -LiteralPath $statePath -Force;$limit=Get-AriaPolicyMaxBytes $policy 'memory.read' 16777216;if([int64]$info.Length-gt$limit){throw "ARIA memory state exceeds policy maxBytes ($limit): $statePath"};$persisted=ConvertTo-AriaHashtable (Read-AriaUtf8Text $statePath|ConvertFrom-Json);foreach($memoryName in $persisted.Keys){if(-not$memories.ContainsKey($memoryName)){throw "ARIA persisted state contains undeclared memory '$memoryName'."};foreach($key in $persisted[$memoryName].Keys){if(-not$memoryTypes[$memoryName].ContainsKey($key)){throw "ARIA persisted state contains undeclared memory key '$memoryName.$key'."};Assert-AriaRuntimeType ([string]$memoryTypes[$memoryName][$key]) $persisted[$memoryName][$key] "persisted memory $memoryName.$key";$memories[$memoryName][$key]=$persisted[$memoryName][$key]}}}
    $context=[pscustomobject]@{bytecode=$bytecode;policy=$policy;workspaceRoot=$WorkspaceRoot;capabilityMap=$capabilityMap;agentMap=$agentMap;functionMap=$functionMap;outputs=$outputs;events=$events;memories=$memories;memoryTypes=$memoryTypes;memoryDirty=$false;passThru=[bool]$PassThru}
    $scopes=New-AriaScopeStack;$result=Invoke-AriaInstructionSequence @($bytecode.instructions) $context $scopes @{} 0;if($result.control-ne'halt'){throw 'ARIA entry flow terminated without HALT.'}
    if($context.memoryDirty){if(-not(Test-Path -LiteralPath $stateRoot)){New-Item -ItemType Directory -Path $stateRoot -Force|Out-Null};Save-AriaMemoryState $statePath $memories $policy}
    return [pscustomobject][ordered]@{programName=$bytecode.programName;outputs=$outputs.ToArray();events=$events.ToArray();variables=$scopes[0];memories=$memories;graphs=$bytecode.graphs;statePath=$statePath;memoryPersisted=$context.memoryDirty}
}
function Invoke-AriaArtifact { param([string]$Path,[string]$PolicyPath,[string]$WorkspaceRoot=(Get-AriaRepositoryRoot),[switch]$PassThru) return(Invoke-AriaContainer (Read-AriaContainer $Path) $PolicyPath $WorkspaceRoot -PassThru:$PassThru) }
Export-ModuleMember -Function Invoke-AriaContainer,Invoke-AriaArtifact
