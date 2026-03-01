```graph TD
    Start([BC_OP_SEND]) --> Arity{Check op2 Arity}
    
    Arity -->|0: Unary, 1: Binary, 2: Keyword| SetupArgs[Setup Arguments on Stack]
    SetupArgs --> LookupPrim[vm_lookup_method_primitive]
    
    LookupPrim --> PrimFound{Native Primitive Found?}
    
    %% Fast Path: Native Primitive
    PrimFound -->|Yes| Dispatch[primitive_dispatch]
    Dispatch --> PrimSuccess{Execution Success?}
    PrimSuccess -->|Yes| Advance([Push Result & Advance IP])
    PrimSuccess -->|No| Fallback
    
    %% Dynamic Path: Block Fallback
    PrimFound -->|No| LookupDyn[vm_lookup_dynamic_method_block]
    LookupDyn --> DynFound{Valid Block in Object Slots?}
    
    DynFound -->|Yes| ExecBlock[primitive_dispatch: PRIM_BLOCK_VALUE]
    ExecBlock --> BlockSuccess{Block Success?}
    BlockSuccess -->|Yes| Advance
    BlockSuccess -->|No| Fallback
    
    DynFound -->|No| Fallback
    
    %% Ultimate Fallback
    Fallback[vm_invoke_primitive_failed] --> FallbackSuccess{primitiveFailed Understood?}
    FallbackSuccess -->|Yes| Advance
    FallbackSuccess -->|No| Halt([Print Error & Halt VM])
```