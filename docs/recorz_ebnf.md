(* ================================================================
   recorz – Simplified EBNF
   Pure Smalltalk-80 / ANSI syntax
   Prototype-based semantics via message sends only
   Lexical self/super in executable code
   No extra syntax for prototypes, slots, or objects
   ================================================================ *)

(* LEXICAL ELEMENTS *)
Character = ? Any Unicode character ? ;
WhitespaceCharacter = ? Any space, newline or horizontal tab character ? ;
DecimalDigit = "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" ;
Letter = "A" | "B" | "C" | "D" | "E" | "F" | "G" | "H" | "I" | "J" | "K" | "L" | "M"
       | "N" | "O" | "P" | "Q" | "R" | "S" | "T" | "U" | "V" | "W" | "X" | "Y" | "Z"
       | "a" | "b" | "c" | "d" | "e" | "f" | "g" | "h" | "i" | "j" | "k" | "l" | "m"
       | "n" | "o" | "p" | "q" | "r" | "s" | "t" | "u" | "v" | "w" | "x" | "y" | "z" ;
CommentCharacter = Character - '"' ;
Comment = '"', {CommentCharacter}, '"' ;
OptionalWhitespace = {WhitespaceCharacter | Comment} ;
Whitespace = (WhitespaceCharacter | Comment), OptionalWhitespace ;

LetterOrDigit = DecimalDigit | Letter ;
Identifier = (Letter | "_"), {(LetterOrDigit | "_")} ;
Reference = Identifier ;

ConstantReference = "nil" | "false" | "true" ;
(* Note: thisContext is intentionally not a language keyword.
   Debugger/context access is provided by reflective objects and messages. *)
PseudoVariableReference = "self" | "super" ;
ReservedIdentifier = PseudoVariableReference | ConstantReference ;
BindableIdentifier = Identifier - ReservedIdentifier ;

UnaryMessageSelector = Identifier ;
Keyword = Identifier, ":" ;
KeywordMessageSelector = Keyword, {Keyword} ;

BinarySelectorChar = "~" | "!" | "@" | "%" | "&" | "*" | "-" | "+" | "=" | "|" | "\" | "<" | ">" | "," | "?" | "/" ;
BinaryMessageSelector = BinarySelectorChar, [BinarySelectorChar] ;

IntegerLiteral = ["-"], UnsignedIntegerLiteral ;
UnsignedIntegerLiteral = DecimalIntegerLiteral | Radix, "r", BaseNIntegerLiteral ;
DecimalIntegerLiteral = DecimalDigit, {DecimalDigit} ;
Radix = DecimalIntegerLiteral ;
BaseNIntegerLiteral = LetterOrDigit, {LetterOrDigit} ;

ScaledDecimalLiteral = ["-"], DecimalIntegerLiteral, [".", DecimalIntegerLiteral], "s", [DecimalIntegerLiteral] ;
FloatingPointLiteral = ["-"], DecimalIntegerLiteral, (".", DecimalIntegerLiteral, [Exponent] | Exponent) ;
Exponent = ("e" | "d" | "q"), ["+" | "-"], DecimalIntegerLiteral ;

CharacterLiteral = "$", Character ;
StringLiteral = "'", {StringLiteralCharacter | "''"}, "'" ;
StringLiteralCharacter = Character - "'" ;

SymbolInArrayLiteral = UnaryMessageSelector - ConstantReference
                     | KeywordMessageSelector
                     | BinaryMessageSelector ;
SymbolLiteral = "#", (SymbolInArrayLiteral | ConstantReference | StringLiteral) ;

ArrayLiteral = ObjectArrayLiteral | ByteArrayLiteral ;
ObjectArrayLiteral = "#", NestedObjectArrayLiteral ;
NestedObjectArrayLiteral = "(", OptionalWhitespace, [LiteralArrayElement, {Whitespace, LiteralArrayElement}], OptionalWhitespace, ")" ;
LiteralArrayElement = Literal - BlockLiteral
                    | NestedObjectArrayLiteral
                    | SymbolInArrayLiteral
                    | ConstantReference ;
ByteArrayLiteral = "#[", OptionalWhitespace, [UnsignedIntegerLiteral, {Whitespace, UnsignedIntegerLiteral}], OptionalWhitespace, "]" ;

FormalBlockArgumentDeclaration = ":", BindableIdentifier ;
FormalBlockArgumentDeclarationList = FormalBlockArgumentDeclaration, {Whitespace, FormalBlockArgumentDeclaration} ;
BlockLiteral = "[", [OptionalWhitespace, FormalBlockArgumentDeclarationList, OptionalWhitespace, "|"], ExecutableCode, OptionalWhitespace, "]" ;

(* CORE SYNTAX *)
Literal = ConstantReference
        | IntegerLiteral
        | ScaledDecimalLiteral
        | FloatingPointLiteral
        | CharacterLiteral
        | StringLiteral
        | SymbolLiteral
        | ArrayLiteral
        | BlockLiteral ;

NestedExpression = "(", Statement, OptionalWhitespace, ")" ;
Operand = Literal | Reference | NestedExpression ;

UnaryMessage = UnaryMessageSelector ;
UnaryMessageChain = {OptionalWhitespace, UnaryMessage} ;

BinaryMessageOperand = Operand, UnaryMessageChain ;
BinaryMessage = BinaryMessageSelector, OptionalWhitespace, BinaryMessageOperand ;
BinaryMessageChain = {OptionalWhitespace, BinaryMessage} ;

KeywordMessageArgument = BinaryMessageOperand, BinaryMessageChain ;
KeywordMessageSegment = Keyword, OptionalWhitespace, KeywordMessageArgument ;
KeywordMessage = KeywordMessageSegment, {OptionalWhitespace, KeywordMessageSegment} ;

MessageChain = UnaryMessage, UnaryMessageChain, BinaryMessageChain, [KeywordMessage]
             | BinaryMessage, BinaryMessageChain, [KeywordMessage]
             | KeywordMessage ;

CascadedMessage = ";", OptionalWhitespace, MessageChain ;

Expression = Operand, [OptionalWhitespace, MessageChain, {OptionalWhitespace, CascadedMessage}] ;

AssignmentOperation = OptionalWhitespace, BindableIdentifier, OptionalWhitespace, ":=" ;
MethodReturnOperator = "^" ;
Statement = [MethodReturnOperator], {AssignmentOperation}, OptionalWhitespace, Expression ;

LocalVariableDeclarationList = OptionalWhitespace, "|", OptionalWhitespace, [BindableIdentifier, {Whitespace, BindableIdentifier}], OptionalWhitespace, "|" ;
PrimitiveDeclaration = "<", OptionalWhitespace, "primitive:", OptionalWhitespace, DecimalIntegerLiteral, OptionalWhitespace, ">" ;
StatementTerminator = OptionalWhitespace, ".", OptionalWhitespace ;
ExecutableCode = [LocalVariableDeclarationList], OptionalWhitespace, [PrimitiveDeclaration, OptionalWhitespace], [Statement, {StatementTerminator, Statement}], [OptionalWhitespace, "."] ;

(* TOP-LEVEL PROGRAM *)
Program = OptionalWhitespace, [ExecutableCode], OptionalWhitespace ;

(* Optional: classic method-definition syntax for runtime use *)
UnaryMethodHeader = UnaryMessageSelector ;
BinaryMethodHeader = BinaryMessageSelector, OptionalWhitespace, BindableIdentifier ;
KeywordMethodHeaderSegment = Keyword, OptionalWhitespace, BindableIdentifier ;
KeywordMethodHeader = KeywordMethodHeaderSegment, {Whitespace, KeywordMethodHeaderSegment} ;
MethodHeader = UnaryMethodHeader | BinaryMethodHeader | KeywordMethodHeader ;
MethodDeclaration = OptionalWhitespace, MethodHeader, ExecutableCode ;
