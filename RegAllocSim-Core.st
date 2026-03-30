"
RegAllocSim-Core
==================
Simulates stack-to-register mapping and merge point behavior
as performed by StackToRegisterMappingCogit in the Pharo VM.

Author: Apex Poudel
Date: March 2026
"

Object subclass: #RaRegisterSlot
	instanceVariableNames: 'name state value'
	classVariableNames: ''
	package: 'RegAllocSim-Core'.

"--- RaRegisterSlot ---"

RaRegisterSlot class >> named: aString
	^ self new name: aString; beEmpty; yourself

RaRegisterSlot >> name
	^ name

RaRegisterSlot >> name: aString
	name := aString

RaRegisterSlot >> state
	^ state

RaRegisterSlot >> value
	^ value

RaRegisterSlot >> beEmpty
	state := #empty.
	value := nil.

RaRegisterSlot >> holdValue: aValue
	state := #holding.
	value := aValue.

RaRegisterSlot >> beSpilled
	state := #spilled.

RaRegisterSlot >> isEmpty
	^ state = #empty

RaRegisterSlot >> isHolding
	^ state = #holding

RaRegisterSlot >> isSpilled
	^ state = #spilled

RaRegisterSlot >> matches: anotherSlot
	"Do both slots hold the same value?"
	^ self isHolding and: [ anotherSlot isHolding and: [
		self value = anotherSlot value ] ]

RaRegisterSlot >> deepCopy
	^ self class new
		name: name;
		state: state;
		value: value;
		yourself

RaRegisterSlot >> state: aSymbol
	state := aSymbol

RaRegisterSlot >> value: anObject
	value := anObject

RaRegisterSlot >> printOn: aStream
	aStream nextPutAll: name; nextPut: $=.
	self isEmpty ifTrue: [ aStream nextPutAll: 'empty' ].
	self isHolding ifTrue: [ aStream nextPutAll: value printString ].
	self isSpilled ifTrue: [ aStream nextPutAll: 'SPILL' ].


"============================================================"

Object subclass: #RaAbstractState
	instanceVariableNames: 'registers stack nextValueId'
	classVariableNames: ''
	package: 'RegAllocSim-Core'.

"--- RaAbstractState ---"

RaAbstractState class >> withRegisters: n
	^ self new initializeWithRegisters: n

RaAbstractState >> initializeWithRegisters: n
	registers := (1 to: n) collect: [ :i |
		RaRegisterSlot named: 'R', (i - 1) printString ].
	stack := OrderedCollection new.
	nextValueId := 0.

RaAbstractState >> registers
	^ registers

RaAbstractState >> stack
	^ stack

RaAbstractState >> registerCount
	^ registers size

RaAbstractState >> usedRegisterCount
	^ (registers select: [ :r | r isHolding ]) size

RaAbstractState >> utilization
	"Percentage of registers currently holding values"
	registers ifEmpty: [ ^ 0.0 ].
	^ self usedRegisterCount / registers size asFloat * 100.0

RaAbstractState >> nextValue
	"Generate a unique value identifier (simulates a new SSA value)"
	nextValueId := nextValueId + 1.
	^ 'val', nextValueId printString

RaAbstractState >> findFreeRegister
	"Return first empty register, or nil if all are occupied"
	^ registers detect: [ :r | r isEmpty ] ifNone: [ nil ]

RaAbstractState >> spillFurthest
	"Spill the register whose value is used furthest in the future.
	 Simplified: just spill the last occupied register."
	| victim |
	victim := registers reversed detect: [ :r | r isHolding ] ifNone: [ ^ nil ].
	stack add: victim value.
	victim beSpilled.
	victim beEmpty. "after spilling, the register is free"
	^ victim

RaAbstractState >> pushValue
	"Simulate a push: allocate a register for a new value.
	 If no registers available, spill one first."
	| reg val |
	val := self nextValue.
	reg := self findFreeRegister.
	reg ifNil: [
		self spillFurthest.
		reg := self findFreeRegister ].
	reg holdValue: val.
	^ val

RaAbstractState >> popValue
	"Simulate a pop: free the most recently filled register.
	 Returns the value that was in the register."
	| reg |
	reg := registers reversed detect: [ :r | r isHolding ] ifNone: [ ^ nil ].
	| val |
	val := reg value.
	reg beEmpty.
	^ val

RaAbstractState >> deepCopy
	| copy |
	copy := self class new.
	copy registers: (registers collect: [ :r | r deepCopy ]).
	copy stack: stack copy.
	copy nextValueId: nextValueId.
	^ copy

RaAbstractState >> registers: aCollection
	registers := aCollection

RaAbstractState >> stack: aCollection
	stack := aCollection

RaAbstractState >> nextValueId: anInteger
	nextValueId := anInteger

RaAbstractState >> printOn: aStream
	aStream nextPut: $[.
	registers
		do: [ :r | r printOn: aStream ]
		separatedBy: [ aStream nextPutAll: ', ' ].
	aStream nextPut: $].
	aStream nextPutAll: ' util='.
	aStream nextPutAll: (self utilization printShowingDecPlaces: 1).
	aStream nextPut: $%.


"============================================================"

Object subclass: #RaStateReconciler
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'RegAllocSim-Core'.

"--- RaStateReconciler class methods ---"

RaStateReconciler class >> flushAllStrategy: stateA and: stateB
	"Current Cogit strategy: flush everything at merge points.
	 Returns a new state with all registers empty."
	| result |
	result := RaAbstractState withRegisters: stateA registerCount.
	^ result

RaStateReconciler class >> reconcileStrategy: stateA and: stateB
	"Proposed strategy: keep registers that agree, spill only conflicts.
	 If both branches have the same value in the same register, keep it.
	 Otherwise, spill to stack."
	| result spillCount |
	result := RaAbstractState withRegisters: stateA registerCount.
	spillCount := 0.
	
	1 to: stateA registerCount do: [ :i |
		| regA regB resultReg |
		regA := stateA registers at: i.
		regB := stateB registers at: i.
		resultReg := result registers at: i.
		
		(regA matches: regB) 
			ifTrue: [
				"Both branches agree — keep the value"
				resultReg holdValue: regA value ]
			ifFalse: [
				"Conflict — need to spill or insert phi"
				(regA isHolding or: [ regB isHolding ]) ifTrue: [
					spillCount := spillCount + 1 ].
				resultReg beEmpty ] ].
	
	^ result -> spillCount

RaStateReconciler class >> compareStrategies: stateA and: stateB
	"Compare flush-all vs reconciliation. Returns a report dictionary."
	| flushed reconciled reconcileResult spillCountFlush spillCountReconcile |
	
	"Flush-all: everything goes to stack"
	flushed := self flushAllStrategy: stateA and: stateB.
	spillCountFlush := stateA usedRegisterCount max: stateB usedRegisterCount.
	
	"Reconciliation: keep agreements, spill conflicts"
	reconcileResult := self reconcileStrategy: stateA and: stateB.
	reconciled := reconcileResult key.
	spillCountReconcile := reconcileResult value.
	
	^ Dictionary new
		at: #stateA put: stateA;
		at: #stateB put: stateB;
		at: #flushedState put: flushed;
		at: #reconciledState put: reconciled;
		at: #spillsFlushAll put: spillCountFlush;
		at: #spillsReconciled put: spillCountReconcile;
		at: #utilizationBefore put: ((stateA utilization + stateB utilization) / 2.0);
		at: #utilizationFlushAll put: flushed utilization;
		at: #utilizationReconciled put: reconciled utilization;
		yourself


"============================================================"

Object subclass: #RaSimulator
	instanceVariableNames: 'numRegisters'
	classVariableNames: ''
	package: 'RegAllocSim-Core'.

"--- RaSimulator ---"

RaSimulator >> availableRegisters: n
	numRegisters := n

RaSimulator >> simulateBranch
	"Simulate a simple method: 
	  push push add | branch | true-path: push push mul | false-path: push add | merge"
	| state stateBeforeBranch stateA stateB |
	
	state := RaAbstractState withRegisters: numRegisters.
	
	"Common prefix: push, push, add"
	state pushValue.
	state pushValue.
	state popValue. state popValue. state pushValue. "simulate add"
	
	"Save state at branch point"
	stateBeforeBranch := state deepCopy.
	
	"Branch A (true path): push, push, multiply"
	stateA := stateBeforeBranch deepCopy.
	stateA pushValue.
	stateA pushValue.
	stateA popValue. stateA popValue. stateA pushValue. "simulate multiply"
	
	"Branch B (false path): push, add"
	stateB := stateBeforeBranch deepCopy.
	stateB pushValue.
	stateB popValue. stateB popValue. stateB pushValue. "simulate add"
	
	"Merge point: compare strategies"
	^ RaStateReconciler compareStrategies: stateA and: stateB

RaSimulator >> report
	"Run simulation and print report"
	| results |
	results := self simulateBranch.
	
	Transcript cr.
	Transcript show: '=== Register Allocation Simulation ==='; cr.
	Transcript show: 'Available registers: ', numRegisters printString; cr.
	Transcript cr.
	
	Transcript show: 'Branch A final state: '; 
		show: (results at: #stateA) printString; cr.
	Transcript show: 'Branch B final state: '; 
		show: (results at: #stateB) printString; cr.
	Transcript cr.
	
	Transcript show: 'Avg utilization before merge: ';
		show: ((results at: #utilizationBefore) printShowingDecPlaces: 1); 
		show: '%'; cr.
	Transcript show: 'Utilization after merge (flush-all): ';
		show: ((results at: #utilizationFlushAll) printShowingDecPlaces: 1);
		show: '%'; cr.
	Transcript show: 'Utilization after merge (reconciled): ';
		show: ((results at: #utilizationReconciled) printShowingDecPlaces: 1);
		show: '%'; cr.
	Transcript cr.
	
	Transcript show: 'Spills with flush-all: ';
		show: (results at: #spillsFlushAll) printString; cr.
	Transcript show: 'Spills with reconciliation: ';
		show: (results at: #spillsReconciled) printString; cr.
	
	(results at: #spillsFlushAll) > 0 ifTrue: [ | improvement |
		improvement := 1.0 - ((results at: #spillsReconciled) / (results at: #spillsFlushAll) asFloat).
		Transcript show: 'Potential improvement: ';
			show: (improvement * 100 printShowingDecPlaces: 1);
			show: '% fewer spills'; cr ].
	
	^ results
