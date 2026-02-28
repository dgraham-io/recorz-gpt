"Root prototype"
ProtoObject := Object clone.     "or whatever your root is"

"Create a new prototype by cloning"
PointProto := ProtoObject clone.

"Add slots (data or assignable) – all via messages"
PointProto addSlot: #x value: 0.           "constant slot"
PointProto addSlot: #y value: 0.           "assignable slot"
PointProto addSlot: #color value: 'red'.

"Add methods via blocks"
PointProto addMethod: #distanceToOrigin 
           do: [ ((self x * self x) + (self y * self y)) sqrt ].

"Clone and use"
p := PointProto clone.
p x: 3; y: 4.          "cascade"
p distanceToOrigin print.

"--- Hardware / Primitive Example ---"
"Demonstrating bare-metal access for the RISC-V VM"
MemoryProto := ProtoObject clone.

MemoryProto addMethod: #byteAt: 
            do: [ :address | 
                <primitive: 10> 
                "Fallback code if primitive fails"
                ^ self primitiveFailed 
            ].

MemoryProto addMethod: #byteAt:put: 
            do: [ :address :value | 
                <primitive: 11> 
                ^ self primitiveFailed 
            ].
