graph TD
    Start([Call vm_alloc_object]) --> LoadPtr[Load vm_heap_ptr]
    LoadPtr --> CheckInit{Is vm_heap_ptr == 0?}
    
    CheckInit -->|Yes| InitPtr[Initialize to base of vm_heap]
    CheckInit -->|No| CalcNext[Use existing pointer]
    
    InitPtr --> AddBytes
    CalcNext --> AddBytes
    
    AddBytes[Calculate: new_ptr = current_ptr + OBJ_BYTES] --> CheckBounds{new_ptr > vm_heap_end?}
    
    CheckBounds -->|Yes| OOM([Out of Memory:<br>a0 = -1, a1 = 0])
    CheckBounds -->|No| Success([Update vm_heap_ptr<br>Return object ptr in a1<br>a0 = 0])