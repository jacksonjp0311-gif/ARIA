Set-StrictMode -Version 2.0

function Get-AriaOpcodeRegistry { $path=Join-Path (Get-AriaRepositoryRoot) 'grammar/opcodes.json';$doc=Read-AriaUtf8Text $path|ConvertFrom-Json;if([string]$doc.format-ne'aria.opcode-registry'){throw 'ARIA opcode registry has an invalid format.'};$registry=[ordered]@{};foreach($opcode in @($doc.opcodes)){$id=[string]$opcode.id;if([string]::IsNullOrWhiteSpace($id)){throw 'ARIA opcode registry contains an empty id.'};if($registry.Contains($id)){throw "ARIA opcode registry contains duplicate id '$id'."};$registry[$id]=$opcode};return $registry }
function Add-AriaConstant { param($Value,$Constants,[hashtable]$Index) $key=if($null-eq$Value){'null'}else{ConvertTo-AriaJson ([pscustomobject][ordered]@{value=$Value})};if($Index.ContainsKey($key)){return [int]$Index[$key]};$position=$Constants.Count;$Constants.Add($Value);$Index[$key]=$position;return $position }
function Get-AriaBinaryOpcode { param([string]$Operator) switch($Operator){'+'{'ADD'}'-'{'SUB'}'*'{'MUL'}'/'{'DIV'}'=='{'EQ'}'!='{'NE'}'<'{'LT'}'<='{'LE'}'>'{'GT'}'>='{'GE'}'and'{'AND'}'or'{'OR'}default{throw "Unknown ARIA operator '$Operator'."}} }

function Add-AriaExpressionInstructions {
    param($Expression,$Instructions,$Constants,[hashtable]$ConstantIndex,[hashtable]$FunctionMap,[int]$Line)
    switch($Expression.kind){
        'literal'{$constant=Add-AriaConstant $Expression.value $Constants $ConstantIndex;$Instructions.Add([pscustomobject][ordered]@{op='PUSH_CONST';arg=$constant;type=[string]$Expression.valueType;line=$Line})}
        'identifier'{$Instructions.Add([pscustomobject][ordered]@{op='LOAD';arg=[string]$Expression.value;line=$Line})}
        'unary'{Add-AriaExpressionInstructions $Expression.operand $Instructions $Constants $ConstantIndex $FunctionMap $Line;$Instructions.Add([pscustomobject][ordered]@{op=$(if($Expression.operator-eq'not'){'NOT'}else{'NEG'});line=$Line})}
        'binary'{Add-AriaExpressionInstructions $Expression.left $Instructions $Constants $ConstantIndex $FunctionMap $Line;Add-AriaExpressionInstructions $Expression.right $Instructions $Constants $ConstantIndex $FunctionMap $Line;$Instructions.Add([pscustomobject][ordered]@{op=(Get-AriaBinaryOpcode $Expression.operator);line=$Line})}
        'call'{foreach($argument in @($Expression.arguments)){Add-AriaExpressionInstructions $argument $Instructions $Constants $ConstantIndex $FunctionMap $Line};$fn=$FunctionMap[[string]$Expression.name];$Instructions.Add([pscustomobject][ordered]@{op='CALL';name=[string]$Expression.name;argCount=@($Expression.arguments).Count;returnType=[string]$fn.returnType;line=$Line})}
        default{throw "Cannot compile expression kind '$($Expression.kind)'."}
    }
}

function ConvertTo-AriaInstructionSequence {
    param([object[]]$Statements,$Constants,[hashtable]$ConstantIndex,[hashtable]$FunctionMap,[switch]$FunctionBody)
    $instructions=New-Object System.Collections.Generic.List[object]
    foreach($statement in $Statements){
        switch($statement.op){
            'emit'{Add-AriaExpressionInstructions $statement.expression $instructions $Constants $ConstantIndex $FunctionMap $statement.line;$instructions.Add([pscustomobject][ordered]@{op='EMIT';line=$statement.line})}
            'signal'{Add-AriaExpressionInstructions $statement.expression $instructions $Constants $ConstantIndex $FunctionMap $statement.line;$instructions.Add([pscustomobject][ordered]@{op='SIGNAL';state=[string]$statement.state;line=$statement.line})}
            'let'{Add-AriaExpressionInstructions $statement.expression $instructions $Constants $ConstantIndex $FunctionMap $statement.line;$instructions.Add([pscustomobject][ordered]@{op='STORE';arg=[string]$statement.name;type=[string]$statement.inferredType;line=$statement.line})}
            'set'{Add-AriaExpressionInstructions $statement.expression $instructions $Constants $ConstantIndex $FunctionMap $statement.line;$instructions.Add([pscustomobject][ordered]@{op='SET';arg=[string]$statement.name;line=$statement.line})}
            'remember'{Add-AriaExpressionInstructions $statement.expression $instructions $Constants $ConstantIndex $FunctionMap $statement.line;$instructions.Add([pscustomobject][ordered]@{op='MEM_SET';memory=[string]$statement.memory;key=[string]$statement.key;line=$statement.line})}
            'recall'{$instructions.Add([pscustomobject][ordered]@{op='MEM_GET';memory=[string]$statement.memory;key=[string]$statement.key;line=$statement.line});$instructions.Add([pscustomobject][ordered]@{op='STORE';arg=[string]$statement.name;type=[string]$statement.inferredType;line=$statement.line})}
            'require'{$instructions.Add([pscustomobject][ordered]@{op='REQUIRE_CAP';arg=[string]$statement.capability;line=$statement.line})}
            'assert'{Add-AriaExpressionInstructions $statement.expression $instructions $Constants $ConstantIndex $FunctionMap $statement.line;$instructions.Add([pscustomobject][ordered]@{op='ASSERT_TRUE';line=$statement.line})}
            'read'{Add-AriaExpressionInstructions $statement.path $instructions $Constants $ConstantIndex $FunctionMap $statement.line;$instructions.Add([pscustomobject][ordered]@{op='FS_READ';arg=[string]$statement.name;type='Text';line=$statement.line})}
            'write'{Add-AriaExpressionInstructions $statement.path $instructions $Constants $ConstantIndex $FunctionMap $statement.line;Add-AriaExpressionInstructions $statement.expression $instructions $Constants $ConstantIndex $FunctionMap $statement.line;$instructions.Add([pscustomobject][ordered]@{op='FS_WRITE';line=$statement.line})}
            'dispatch'{Add-AriaExpressionInstructions $statement.expression $instructions $Constants $ConstantIndex $FunctionMap $statement.line;$instructions.Add([pscustomobject][ordered]@{op='AGENT_DISPATCH';agent=[string]$statement.agent;line=$statement.line})}
            'connect'{$instructions.Add([pscustomobject][ordered]@{op='CONNECT_OPEN';connection=[string]$statement.connection;line=$statement.line})}
            'intent'{Add-AriaExpressionInstructions $statement.expression $instructions $Constants $ConstantIndex $FunctionMap $statement.line;$instructions.Add([pscustomobject][ordered]@{op='CONNECT_INTENT';connection=[string]$statement.connection;line=$statement.line})}
            'propose'{Add-AriaExpressionInstructions $statement.expression $instructions $Constants $ConstantIndex $FunctionMap $statement.line;$instructions.Add([pscustomobject][ordered]@{op='CONNECT_PROPOSE';connection=[string]$statement.connection;line=$statement.line})}
            'consent'{Add-AriaExpressionInstructions $statement.expression $instructions $Constants $ConstantIndex $FunctionMap $statement.line;$instructions.Add([pscustomobject][ordered]@{op='CONNECT_CONSENT';connection=[string]$statement.connection;line=$statement.line})}
            'disconnect'{$instructions.Add([pscustomobject][ordered]@{op='CONNECT_CLOSE';connection=[string]$statement.connection;line=$statement.line})}
            'if'{Add-AriaExpressionInstructions $statement.condition $instructions $Constants $ConstantIndex $FunctionMap $statement.line;$thenCode=ConvertTo-AriaInstructionSequence @($statement.then) $Constants $ConstantIndex $FunctionMap -FunctionBody:$FunctionBody;$elseCode=ConvertTo-AriaInstructionSequence @($statement.else) $Constants $ConstantIndex $FunctionMap -FunctionBody:$FunctionBody;$instructions.Add([pscustomobject][ordered]@{op='IF';then=@($thenCode);else=@($elseCode);line=$statement.line})}
            'repeat'{Add-AriaExpressionInstructions $statement.count $instructions $Constants $ConstantIndex $FunctionMap $statement.line;$body=ConvertTo-AriaInstructionSequence @($statement.body) $Constants $ConstantIndex $FunctionMap -FunctionBody:$FunctionBody;$instructions.Add([pscustomobject][ordered]@{op='REPEAT';iterator=[string]$statement.iterator;body=@($body);max=10000;line=$statement.line})}
            'return'{if($null-ne$statement.expression){Add-AriaExpressionInstructions $statement.expression $instructions $Constants $ConstantIndex $FunctionMap $statement.line};$instructions.Add([pscustomobject][ordered]@{op='RETURN';hasValue=($null-ne$statement.expression);line=$statement.line})}
            'halt'{$instructions.Add([pscustomobject][ordered]@{op='HALT';line=$statement.line})}
        }
    }
    return $instructions.ToArray()
}

function ConvertTo-AriaBytecodeModel {
    param($SemanticResult,[string]$SourceText)
    $model=$SemanticResult.model;$constants=New-Object System.Collections.Generic.List[object];$constantIndex=@{};$functionMap=$SemanticResult.functionMap
    $entry=@($model.flows|Where-Object{$_.name-eq$model.entry})[0]
    [object[]]$instructions=@(ConvertTo-AriaInstructionSequence @($entry.statements) $constants $constantIndex $functionMap)
    if($instructions.Count-eq0-or$instructions[$instructions.Count-1].op-ne'HALT'){$instructions+=,[pscustomobject][ordered]@{op='HALT';line=0}}
    $functions=New-Object System.Collections.Generic.List[object]
    foreach($fn in $model.functions){[object[]]$body=@(ConvertTo-AriaInstructionSequence @($fn.statements) $constants $constantIndex $functionMap -FunctionBody);if($fn.returnType-eq'Null'-and($body.Count-eq0-or$body[$body.Count-1].op-ne'RETURN')){$body+=,[pscustomobject][ordered]@{op='RETURN';hasValue=$false;line=0}};$functions.Add([pscustomobject][ordered]@{name=$fn.name;parameters=$fn.parameters;returnType=$fn.returnType;instructions=$body})}
    $memories=New-Object System.Collections.Generic.List[object]
    foreach($memory in $model.memories){$values=[ordered]@{};$types=[ordered]@{};foreach($entryValue in $memory.values){$values[$entryValue.key]=$entryValue.expression.value;$types[$entryValue.key]=[string]$entryValue.inferredType};$memories.Add([pscustomobject][ordered]@{name=$memory.name;values=[pscustomobject]$values;types=[pscustomobject]$types})}
    $sourceHash=Get-AriaSha256Text $SourceText
    $ir=[pscustomobject][ordered]@{format=$model.format;specVersion=$model.specVersion;moduleName=$model.moduleName;moduleVersion=$model.moduleVersion;programName=$model.programName;programVersion=$model.programVersion;entry=$model.entry;memories=$model.memories;capabilities=$model.capabilities;agents=$model.agents;connections=$model.connections;graphs=$model.graphs;functions=$model.functions;flows=$model.flows}
    return [pscustomobject][ordered]@{format='aria.bytecode';containerVersion=1;compilerVersion=Get-AriaCompilerVersion;specVersion=$model.specVersion;moduleName=$model.moduleName;moduleVersion=$model.moduleVersion;programName=$model.programName;programVersion=$model.programVersion;sourceHash=$sourceHash;irHash=(Get-AriaSha256Text (ConvertTo-AriaJson $ir));entry=$model.entry;constants=$constants.ToArray();memories=$memories.ToArray();capabilities=$model.capabilities;agents=$model.agents;connections=$model.connections;graphs=$model.graphs;functions=$functions.ToArray();instructions=$instructions}
}

function Test-AriaBytecodeIdentifier { param($Value) return (($Value-is[string])-and([string]$Value-match'^[A-Za-z_][A-Za-z0-9_.-]*$')) }
function Test-AriaBytecodeInteger { param($Value) return ($Value-is[byte]-or$Value-is[sbyte]-or$Value-is[int16]-or$Value-is[uint16]-or$Value-is[int32]-or$Value-is[uint32]-or$Value-is[int64]-or$Value-is[uint64]) }
function Test-AriaBytecodeScalar { param($Value) if($null-eq$Value){return $true};return($Value-is[string]-or$Value-is[bool]-or$Value-is[byte]-or$Value-is[sbyte]-or$Value-is[int16]-or$Value-is[uint16]-or$Value-is[int32]-or$Value-is[uint32]-or$Value-is[int64]-or$Value-is[uint64]-or$Value-is[single]-or$Value-is[double]-or$Value-is[decimal]) }
function Test-AriaInstructionHasProperty { param($Instruction,[string]$Name) return ($null-ne$Instruction-and$null-ne($Instruction.PSObject.Properties|Where-Object{$_.Name-eq$Name}|Select-Object -First 1)) }
function Get-AriaValueType { param($Value) if($null-eq$Value){return 'Null'};if($Value-is[bool]){return 'Bool'};if($Value-is[string]){return 'Text'};if($Value-is[byte]-or$Value-is[sbyte]-or$Value-is[int16]-or$Value-is[uint16]-or$Value-is[int32]-or$Value-is[uint32]-or$Value-is[int64]-or$Value-is[uint64]-or$Value-is[single]-or$Value-is[double]-or$Value-is[decimal]){return 'Number'};return 'Any' }
function Copy-AriaVerifierTable { param([hashtable]$Table) $copy=@{};foreach($key in $Table.Keys){$copy[$key]=$Table[$key]};return $copy }
function Pop-AriaVerifierType { param($Stack,$Errors,[string]$Context) if($Stack.Count-eq0){$Errors.Add("Stack underflow at $Context.");return 'Any'};$index=$Stack.Count-1;$value=[string]$Stack[$index];$Stack.RemoveAt($index);return $value }
function Push-AriaVerifierType { param($Stack,[string]$Type,[ref]$Maximum) $null=$Stack.Add($Type);if($Stack.Count-gt$Maximum.Value){$Maximum.Value=$Stack.Count} }

function Test-AriaInstructionSequence {
    param(
        [object[]]$Instructions,
        [hashtable]$Variables,
        [hashtable]$Effects,
        [hashtable]$Functions,
        [hashtable]$MemoryTypes,
        [hashtable]$CapabilityMap,
        [hashtable]$AgentMap,
        [hashtable]$ConnectionMap,
        [object[]]$Constants,
        $Errors,
        [string]$ReturnType,
        [bool]$IsFunction,
        [bool]$IsTopLevel
    )

    $stack = New-Object Collections.ArrayList
    $maximum = 0
    $terminated = $false

    for ($index = 0; $index -lt $Instructions.Count; $index++) {
        $instruction = $Instructions[$index]
        if ($null -eq $instruction -or -not (Test-AriaInstructionHasProperty $instruction 'op')) {
            $Errors.Add("Instruction $index has no opcode.")
            continue
        }

        $op = [string]$instruction.op
        if ($terminated) { $Errors.Add("Instruction $index occurs after control termination.") }
        if (-not (Test-AriaInstructionHasProperty $instruction 'line') -or
            -not (Test-AriaBytecodeInteger $instruction.line) -or
            [int64]$instruction.line -lt 0) {
            $Errors.Add("Instruction $index has an invalid source line.")
        }

        switch ($op) {
            'PUSH_CONST' {
                if (-not (Test-AriaInstructionHasProperty $instruction 'arg') -or
                    -not (Test-AriaBytecodeInteger $instruction.arg) -or
                    [int]$instruction.arg -lt 0 -or
                    [int]$instruction.arg -ge $Constants.Count) {
                    $Errors.Add("PUSH_CONST at $index has an invalid constant index.")
                    Push-AriaVerifierType $stack 'Any' ([ref]$maximum)
                }
                else {
                    Push-AriaVerifierType $stack (Get-AriaValueType $Constants[[int]$instruction.arg]) ([ref]$maximum)
                }
            }
            'LOAD' {
                $name = [string]$instruction.arg
                if (-not $Variables.ContainsKey($name)) {
                    $Errors.Add("LOAD at $index references undefined variable '$name'.")
                    Push-AriaVerifierType $stack 'Any' ([ref]$maximum)
                }
                else { Push-AriaVerifierType $stack ([string]$Variables[$name]) ([ref]$maximum) }
            }
            'STORE' {
                $actual = Pop-AriaVerifierType $stack $Errors "STORE instruction $index"
                $type = [string]$instruction.type
                if ($type -notin @('Any','Text','Number','Bool','Null')) { $Errors.Add("STORE at $index has invalid type '$type'.") }
                if (-not (Test-AriaTypeAssignable $type $actual)) { $Errors.Add("STORE at $index expects $type, received $actual.") }
                $Variables[[string]$instruction.arg] = $type
            }
            'SET' {
                $actual = Pop-AriaVerifierType $stack $Errors "SET instruction $index"
                $name = [string]$instruction.arg
                if (-not $Variables.ContainsKey($name)) { $Errors.Add("SET at $index references undefined variable '$name'.") }
                elseif (-not (Test-AriaTypeAssignable ([string]$Variables[$name]) $actual)) {
                    $Errors.Add("SET at $index expects $($Variables[$name]), received $actual.")
                }
            }
            'ADD' {
                $right = Pop-AriaVerifierType $stack $Errors "ADD instruction $index"
                $left = Pop-AriaVerifierType $stack $Errors "ADD instruction $index"
                if ($left -eq 'Text' -and $right -eq 'Text') { $result = 'Text' }
                elseif ((Test-AriaTypeAssignable 'Number' $left) -and (Test-AriaTypeAssignable 'Number' $right)) { $result = 'Number' }
                else { $Errors.Add("ADD at $index requires Number+Number or Text+Text, received $left+$right."); $result = 'Any' }
                Push-AriaVerifierType $stack $result ([ref]$maximum)
            }
            { $_ -in @('SUB','MUL','DIV') } {
                $right = Pop-AriaVerifierType $stack $Errors "$op instruction $index"
                $left = Pop-AriaVerifierType $stack $Errors "$op instruction $index"
                if (-not ((Test-AriaTypeAssignable 'Number' $left) -and (Test-AriaTypeAssignable 'Number' $right))) {
                    $Errors.Add("$op at $index requires Number operands, received $left and $right.")
                }
                Push-AriaVerifierType $stack 'Number' ([ref]$maximum)
            }
            { $_ -in @('LT','LE','GT','GE') } {
                $right = Pop-AriaVerifierType $stack $Errors "$op instruction $index"
                $left = Pop-AriaVerifierType $stack $Errors "$op instruction $index"
                if (-not ((Test-AriaTypeAssignable 'Number' $left) -and (Test-AriaTypeAssignable 'Number' $right))) {
                    $Errors.Add("$op at $index requires Number operands, received $left and $right.")
                }
                Push-AriaVerifierType $stack 'Bool' ([ref]$maximum)
            }
            { $_ -in @('EQ','NE') } {
                $right = Pop-AriaVerifierType $stack $Errors "$op instruction $index"
                $left = Pop-AriaVerifierType $stack $Errors "$op instruction $index"
                if (-not ((Test-AriaTypeAssignable $left $right) -or (Test-AriaTypeAssignable $right $left))) {
                    $Errors.Add("$op at $index compares incompatible types $left and $right.")
                }
                Push-AriaVerifierType $stack 'Bool' ([ref]$maximum)
            }
            { $_ -in @('AND','OR') } {
                $right = Pop-AriaVerifierType $stack $Errors "$op instruction $index"
                $left = Pop-AriaVerifierType $stack $Errors "$op instruction $index"
                if (-not ((Test-AriaTypeAssignable 'Bool' $left) -and (Test-AriaTypeAssignable 'Bool' $right))) {
                    $Errors.Add("$op at $index requires Bool operands, received $left and $right.")
                }
                Push-AriaVerifierType $stack 'Bool' ([ref]$maximum)
            }
            'NOT' {
                $actual = Pop-AriaVerifierType $stack $Errors "NOT instruction $index"
                if (-not (Test-AriaTypeAssignable 'Bool' $actual)) { $Errors.Add("NOT at $index requires Bool, received $actual.") }
                Push-AriaVerifierType $stack 'Bool' ([ref]$maximum)
            }
            'NEG' {
                $actual = Pop-AriaVerifierType $stack $Errors "NEG instruction $index"
                if (-not (Test-AriaTypeAssignable 'Number' $actual)) { $Errors.Add("NEG at $index requires Number, received $actual.") }
                Push-AriaVerifierType $stack 'Number' ([ref]$maximum)
            }
            { $_ -in @('EMIT','SIGNAL','ASSERT_TRUE','AGENT_DISPATCH') } {
                $value = Pop-AriaVerifierType $stack $Errors "$op instruction $index"
                if ($op -eq 'ASSERT_TRUE' -and -not (Test-AriaTypeAssignable 'Bool' $value)) {
                    $Errors.Add("ASSERT_TRUE at $index requires Bool, received $value.")
                }
                if ($op -eq 'AGENT_DISPATCH') {
                    if (-not (Test-AriaTypeAssignable 'Text' $value)) { $Errors.Add("AGENT_DISPATCH at $index requires Text task, received $value.") }
                    if (-not $AgentMap.ContainsKey([string]$instruction.agent)) { $Errors.Add("AGENT_DISPATCH at $index references unknown agent '$($instruction.agent)'.") }
                }
            }
            { $_ -in @('CONNECT_OPEN','CONNECT_CLOSE') } {
                $name = [string]$instruction.connection
                if (-not $ConnectionMap.ContainsKey($name)) { $Errors.Add("$op at $index references unknown connection '$name'.") }
            }
            { $_ -in @('CONNECT_INTENT','CONNECT_PROPOSE','CONNECT_CONSENT') } {
                $value = Pop-AriaVerifierType $stack $Errors "$op instruction $index"
                $name = [string]$instruction.connection
                if (-not $ConnectionMap.ContainsKey($name)) { $Errors.Add("$op at $index references unknown connection '$name'.") }
                $expected = if ($op -eq 'CONNECT_CONSENT') { 'Bool' } else { 'Text' }
                if (-not (Test-AriaTypeAssignable $expected $value)) { $Errors.Add("$op at $index requires $expected, received $value.") }
            }
            'MEM_SET' {
                $actual = Pop-AriaVerifierType $stack $Errors "MEM_SET instruction $index"
                $memory = [string]$instruction.memory
                $key = [string]$instruction.key
                if (-not $MemoryTypes.ContainsKey($memory) -or -not $MemoryTypes[$memory].ContainsKey($key)) {
                    $Errors.Add("MEM_SET at $index references unknown memory '$memory.$key'.")
                }
                elseif (-not (Test-AriaTypeAssignable ([string]$MemoryTypes[$memory][$key]) $actual)) {
                    $Errors.Add("MEM_SET at $index expects $($MemoryTypes[$memory][$key]), received $actual.")
                }
            }
            'MEM_GET' {
                $memory = [string]$instruction.memory
                $key = [string]$instruction.key
                if (-not $MemoryTypes.ContainsKey($memory) -or -not $MemoryTypes[$memory].ContainsKey($key)) {
                    $Errors.Add("MEM_GET at $index references unknown memory '$memory.$key'.")
                    Push-AriaVerifierType $stack 'Any' ([ref]$maximum)
                }
                else { Push-AriaVerifierType $stack ([string]$MemoryTypes[$memory][$key]) ([ref]$maximum) }
            }
            'REQUIRE_CAP' {
                $name = [string]$instruction.arg
                if (-not $CapabilityMap.ContainsKey($name)) { $Errors.Add("REQUIRE_CAP at $index references unknown capability '$name'.") }
                else { $Effects[[string]$CapabilityMap[$name].effect] = $true }
            }
            'FS_READ' {
                $pathType = Pop-AriaVerifierType $stack $Errors "FS_READ instruction $index"
                if (-not $Effects.ContainsKey('fs.read')) { $Errors.Add("FS_READ at $index has no active fs.read capability.") }
                if (-not (Test-AriaTypeAssignable 'Text' $pathType)) { $Errors.Add("FS_READ at $index requires Text path, received $pathType.") }
                $Variables[[string]$instruction.arg] = 'Text'
            }
            'FS_WRITE' {
                $valueType = Pop-AriaVerifierType $stack $Errors "FS_WRITE instruction $index"
                $pathType = Pop-AriaVerifierType $stack $Errors "FS_WRITE instruction $index"
                if (-not $Effects.ContainsKey('fs.write')) { $Errors.Add("FS_WRITE at $index has no active fs.write capability.") }
                if (-not (Test-AriaTypeAssignable 'Text' $pathType) -or -not (Test-AriaTypeAssignable 'Text' $valueType)) {
                    $Errors.Add("FS_WRITE at $index requires Text path and value.")
                }
            }
            'CALL' {
                $name = [string]$instruction.name
                $argCount = if (Test-AriaInstructionHasProperty $instruction 'argCount') { [int]$instruction.argCount } else { -1 }
                if ($argCount -lt 0 -or $argCount -gt 1024) {
                    $Errors.Add("CALL at $index has invalid argument count.")
                    $argCount = 0
                }
                $args = New-Object System.Collections.Generic.List[string]
                for ($a = 0; $a -lt $argCount; $a++) { $args.Add((Pop-AriaVerifierType $stack $Errors "CALL instruction $index")) }
                if (-not $Functions.ContainsKey($name)) {
                    $Errors.Add("CALL at $index references unknown function '$name'.")
                    Push-AriaVerifierType $stack 'Any' ([ref]$maximum)
                }
                else {
                    $fn = $Functions[$name]
                    if ($argCount -ne @($fn.parameters).Count) { $Errors.Add("CALL at $index has wrong argument count for '$name'.") }
                    for ($a = 0; $a -lt $args.Count -and $a -lt @($fn.parameters).Count; $a++) {
                        $actual = $args[$args.Count - 1 - $a]
                        $expected = [string]$fn.parameters[$a].type
                        if (-not (Test-AriaTypeAssignable $expected $actual)) { $Errors.Add("CALL at $index argument $($a + 1) expects $expected, received $actual.") }
                    }
                    # CALL always leaves one result on the operand stack, including Null.
                    Push-AriaVerifierType $stack ([string]$fn.returnType) ([ref]$maximum)
                }
            }
            'IF' {
                $condition = Pop-AriaVerifierType $stack $Errors "IF instruction $index"
                if (-not (Test-AriaTypeAssignable 'Bool' $condition)) { $Errors.Add("IF at $index requires Bool, received $condition.") }
                $thenResult = Test-AriaInstructionSequence @($instruction.then) (Copy-AriaVerifierTable $Variables) (Copy-AriaVerifierTable $Effects) $Functions $MemoryTypes $CapabilityMap $AgentMap $ConnectionMap $Constants $Errors $ReturnType $IsFunction $false
                $elseResult = Test-AriaInstructionSequence @($instruction.else) (Copy-AriaVerifierTable $Variables) (Copy-AriaVerifierTable $Effects) $Functions $MemoryTypes $CapabilityMap $AgentMap $ConnectionMap $Constants $Errors $ReturnType $IsFunction $false
                $maximum = [math]::Max($maximum, [math]::Max($thenResult.maxStack, $elseResult.maxStack))
                if ($thenResult.terminated -and $elseResult.terminated) { $terminated = $true }
            }
            'REPEAT' {
                $countType = Pop-AriaVerifierType $stack $Errors "REPEAT instruction $index"
                if (-not (Test-AriaTypeAssignable 'Number' $countType)) { $Errors.Add("REPEAT at $index requires Number, received $countType.") }
                $child = Copy-AriaVerifierTable $Variables
                $child[[string]$instruction.iterator] = 'Number'
                $bodyResult = Test-AriaInstructionSequence @($instruction.body) $child (Copy-AriaVerifierTable $Effects) $Functions $MemoryTypes $CapabilityMap $AgentMap $ConnectionMap $Constants $Errors $ReturnType $IsFunction $false
                $maximum = [math]::Max($maximum, $bodyResult.maxStack)
            }
            'RETURN' {
                if (-not $IsFunction) { $Errors.Add("RETURN at $index occurs outside a function.") }
                else {
                    $actual = if ([bool]$instruction.hasValue) { Pop-AriaVerifierType $stack $Errors "RETURN instruction $index" } else { 'Null' }
                    if (-not (Test-AriaTypeAssignable $ReturnType $actual)) { $Errors.Add("RETURN at $index expects $ReturnType, received $actual.") }
                    $terminated = $true
                }
            }
            'HALT' {
                if (-not $IsTopLevel) { $Errors.Add("HALT at $index occurs outside the entry flow.") }
                $terminated = $true
            }
            default { $Errors.Add("Unknown opcode '$op' at instruction $index.") }
        }
    }

    if ($stack.Count -ne 0) { $Errors.Add("Instruction sequence terminates with stack depth $($stack.Count) instead of zero.") }
    return [pscustomobject]@{ maxStack = $maximum; terminated = $terminated }
}

function Test-AriaBytecodeModel {
    param($BytecodeModel)
    $errors=New-Object System.Collections.Generic.List[string];if($null-eq$BytecodeModel){$errors.Add('Bytecode model is null.');return [pscustomobject]@{valid=$false;errors=$errors.ToArray();maxStack=0}}
    $lock=Get-AriaLock;if([string]$BytecodeModel.format-ne'aria.bytecode'){$errors.Add("Invalid bytecode format '$($BytecodeModel.format)'.")};if([string]$BytecodeModel.compilerVersion-ne[string]$lock.compilerVersion){$errors.Add('Bytecode compiler version does not match lock.')};if([string]$BytecodeModel.specVersion-ne[string]$lock.specVersion){$errors.Add('Bytecode spec version does not match lock.')};if(-not(Test-AriaBytecodeIdentifier $BytecodeModel.programName)){$errors.Add('Bytecode program name is invalid.')}
    [object[]]$constants=@($BytecodeModel.constants);foreach($constant in $constants){if(-not(Test-AriaBytecodeScalar $constant)){$errors.Add('Constant pool contains a non-scalar value.')}}
    $memoryTypes=@{};foreach($memory in @($BytecodeModel.memories)){$fields=@{};foreach($property in $memory.types.PSObject.Properties){$fields[$property.Name]=[string]$property.Value};$memoryTypes[[string]$memory.name]=$fields}
    $capabilityMap=@{};foreach($cap in @($BytecodeModel.capabilities)){$capabilityMap[[string]$cap.name]=$cap}
    $agentMap=@{};foreach($agent in @($BytecodeModel.agents)){$agentMap[[string]$agent.name]=$agent}
    $connectionMap=@{};foreach($connection in @($BytecodeModel.connections)){if($connectionMap.ContainsKey([string]$connection.name)){$errors.Add("Duplicate bytecode connection '$($connection.name)'.")}else{$connectionMap[[string]$connection.name]=$connection}}
    $functions=@{};foreach($fn in @($BytecodeModel.functions)){if($functions.ContainsKey([string]$fn.name)){$errors.Add("Duplicate bytecode function '$($fn.name)'.")}else{$functions[[string]$fn.name]=$fn}}
    $max=0;foreach($fn in @($BytecodeModel.functions)){$vars=@{};foreach($param in @($fn.parameters)){$vars[[string]$param.name]=[string]$param.type};$result=Test-AriaInstructionSequence @($fn.instructions) $vars @{} $functions $memoryTypes $capabilityMap $agentMap $connectionMap $constants $errors ([string]$fn.returnType) $true $false;$max=[math]::Max($max,$result.maxStack);if(-not$result.terminated){$errors.Add("Function '$($fn.name)' does not terminate with RETURN.")}}
    $entryResult=Test-AriaInstructionSequence @($BytecodeModel.instructions) @{} @{} $functions $memoryTypes $capabilityMap $agentMap $connectionMap $constants $errors 'Null' $false $true;$max=[math]::Max($max,$entryResult.maxStack);if(-not$entryResult.terminated){$errors.Add('Entry instruction stream does not terminate with HALT.')}
    return [pscustomobject][ordered]@{valid=($errors.Count-eq0);errors=$errors.ToArray();maxStack=$max}
}

function Get-AriaContainerLimits { return [pscustomobject]@{headerBytes=48;maxRawBytes=67108864;maxCompressedBytes=16777216} }
function ConvertTo-AriaContainerBytes { param($BytecodeModel) $limits=Get-AriaContainerLimits;$json=ConvertTo-AriaJson $BytecodeModel;$encoding=New-Object Text.UTF8Encoding($false);$raw=$encoding.GetBytes($json);if($raw.Length-gt$limits.maxRawBytes){throw 'ARIA payload exceeds container limit.'};$sha=[Security.Cryptography.SHA256]::Create();try{$digest=$sha.ComputeHash($raw)}finally{$sha.Dispose()};$compressedStream=New-Object IO.MemoryStream;$gzip=New-Object IO.Compression.GZipStream($compressedStream,[IO.Compression.CompressionMode]::Compress,$true);try{$gzip.Write($raw,0,$raw.Length)}finally{$gzip.Dispose()};$compressed=$compressedStream.ToArray();$compressedStream.Dispose();if($compressed.Length-gt$limits.maxCompressedBytes){throw 'ARIA compressed payload exceeds container limit.'};$stream=New-Object IO.MemoryStream;$writer=New-Object IO.BinaryWriter($stream);try{$writer.Write([Text.Encoding]::ASCII.GetBytes('ARIA'));$writer.Write([byte]1);$writer.Write([byte]1);$writer.Write([uint16]0);$writer.Write([uint32]$raw.Length);$writer.Write([uint32]$compressed.Length);$writer.Write([byte[]]$digest);$writer.Write([byte[]]$compressed);$writer.Flush();$bytes=$stream.ToArray()}finally{$writer.Dispose();$stream.Dispose()};return,$bytes }
function Read-AriaContainerBytes { param([byte[]]$Bytes) $limits=Get-AriaContainerLimits;if($Bytes.Length-lt$limits.headerBytes){throw 'ARIA container is shorter than its fixed header.'};$stream=New-Object -TypeName IO.MemoryStream -ArgumentList (,$Bytes);$reader=New-Object IO.BinaryReader($stream);try{$magic=[Text.Encoding]::ASCII.GetString($reader.ReadBytes(4));if($magic-ne'ARIA'){throw 'Invalid ARIA container magic.'};$version=$reader.ReadByte();$compression=$reader.ReadByte();$reserved=$reader.ReadUInt16();$rawLength=[uint64]$reader.ReadUInt32();$compressedLength=[uint64]$reader.ReadUInt32();$expected=$reader.ReadBytes(32);if($reserved-ne0-or$version-ne1-or$compression-ne1){throw 'Unsupported ARIA container header.'};if($rawLength-gt[uint64]$limits.maxRawBytes-or$compressedLength-gt[uint64]$limits.maxCompressedBytes){throw 'ARIA container exceeds limits.'};if(($limits.headerBytes+$compressedLength)-ne[uint64]$Bytes.Length){throw 'ARIA container encoded length does not match its header.'};$compressed=$reader.ReadBytes([int]$compressedLength)}finally{$reader.Dispose();$stream.Dispose()};$input=New-Object -TypeName IO.MemoryStream -ArgumentList (,$compressed);$gzip=New-Object IO.Compression.GZipStream($input,[IO.Compression.CompressionMode]::Decompress);$rawStream=New-Object IO.MemoryStream;$buffer=New-Object byte[] 8192;$total=0L;try{while(($read=$gzip.Read($buffer,0,$buffer.Length))-gt0){$total+=$read;if($total-gt[int64]$rawLength){throw 'ARIA decompressed payload exceeds declared length.'};$rawStream.Write($buffer,0,$read)}}finally{$gzip.Dispose();$input.Dispose()};$raw=$rawStream.ToArray();$rawStream.Dispose();if($raw.Length-ne[int]$rawLength){throw 'ARIA payload length verification failed.'};$sha=[Security.Cryptography.SHA256]::Create();try{$actual=$sha.ComputeHash($raw)}finally{$sha.Dispose()};if([BitConverter]::ToString($actual)-ne[BitConverter]::ToString($expected)){throw 'ARIA payload digest verification failed.'};$utf8=New-Object Text.UTF8Encoding($false,$true);$json=$utf8.GetString($raw);$model=$json|ConvertFrom-Json;return [pscustomobject][ordered]@{containerVersion=$version;compression='gzip';payloadHash=([BitConverter]::ToString($actual).Replace('-','').ToLowerInvariant());bytecode=$model} }
function Write-AriaContainer { param([byte[]]$Bytes,[string]$Path) $parent=Split-Path -Parent $Path;if($parent-and-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null};[IO.File]::WriteAllBytes($Path,$Bytes) }
function Read-AriaContainer { param([string]$Path) return(Read-AriaContainerBytes ([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).Path))) }
function Add-AriaDisassemblyLines { param($Instructions,$Lines,[int]$Depth=0) for($i=0;$i-lt@($Instructions).Count;$i++){$ins=$Instructions[$i];$details=@();foreach($p in $ins.PSObject.Properties){if($p.Name-notin@('op','line','then','else','body')){$details+="$($p.Name)=$($p.Value)"}};$Lines.Add((('  '*$Depth)+'{0:D4}  {1,-16} {2}'-f$i,$ins.op,($details-join' ')).TrimEnd());if($ins.op-eq'IF'){$Lines.Add(('  '*($Depth+1))+'THEN');Add-AriaDisassemblyLines @($ins.then) $Lines ($Depth+2);if(@($ins.else).Count-gt0){$Lines.Add(('  '*($Depth+1))+'ELSE');Add-AriaDisassemblyLines @($ins.else) $Lines ($Depth+2)}}elseif($ins.op-eq'REPEAT'){Add-AriaDisassemblyLines @($ins.body) $Lines ($Depth+1)}} }
function Format-AriaDisassembly { param($Container) $lines=New-Object System.Collections.Generic.List[string];$bc=$Container.bytecode;$lines.Add("ARIA $($bc.specVersion) :: $($bc.programName)@$($bc.programVersion)");$lines.Add("compiler=$($bc.compilerVersion) source=$($bc.sourceHash) payload=$($Container.payloadHash)");foreach($fn in @($bc.functions)){$lines.Add('');$lines.Add("FUNCTION $($fn.name) -> $($fn.returnType)");Add-AriaDisassemblyLines @($fn.instructions) $lines 1};$lines.Add('');$lines.Add('ENTRY');Add-AriaDisassemblyLines @($bc.instructions) $lines 1;return($lines-join[Environment]::NewLine) }

Export-ModuleMember -Function Get-AriaOpcodeRegistry,ConvertTo-AriaBytecodeModel,Test-AriaBytecodeModel,Get-AriaContainerLimits,ConvertTo-AriaContainerBytes,Read-AriaContainerBytes,Write-AriaContainer,Read-AriaContainer,Format-AriaDisassembly
