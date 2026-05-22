"""
    to_smtlib2(expr; output_file = "output.smt2")

Main entry point that converts a symbolic expression to SMTLIB2 format and saves it to a file.

This function orchestrates the entire conversion process by:
1. Collecting all variables and outputs from the expression tree
2. Generating the SMTLIB2 code
3. Writing the result to a file

# Arguments
- `expr`: A symbolic expression (typically a decision tree or logic formula)
- `output_file`: Path where the SMTLIB2 file will be saved (default: "output.smt2")

# Keyword Arguments
- `force_input::Vector{String}=[]`: use this to force the writing of a new
    variable in the header "Input variables" section;
- `force_output::Vector{String}=[]`: similar to `force_input`.

# Returns
- The generated SMTLIB2 code as a string

# Examples
```julia
# Given an expression like: (V1 < 0.5) ∧ ([o1] == 1.0)
expr = some_symbolic_expression
smt_code = to_smtlib2(expr, output_file = "my_constraints.smt2")
# Output: "SMTLIB2 file generated: my_constraints.smt2"
# Creates file containing:
# (set-logic QF_LIRA)
# (declare-const V1 Real)
# (declare-const o1 Real)
# (assert (and (< V1 0.5) (= o1 1.0)))
# (check-sat)
# (get-model)
```
"""
function to_smtlib2(
    expr;
    output_file::Union{Nothing,String}=nothing,
    force_input=String[],
    force_output=String[],
    integerfeatures=Int[],
    typeof_output=1,
    kwargs...,
)
    # Initialize empty sets to collect variable names
    vars = Set{String}()
    outputs = Set{String}()

    # Extract all variable and output names from the expression tree
    collect_symbols!(expr, vars, outputs)

    for fi in force_input
        push!(vars, fi)
    end

    for fo in force_output
        push!(outputs, fo)
    end

    # Convert the expression to SMTLIB2 format
    smt_code = generate_smtlib2(
        expr, vars, outputs; integerfeatures, typeof_output, kwargs...
    )

    # Remove the additionam Atom{String}(...) which encodes the Or (in the regression case)
    # or the Oc (classification) that, in `forest_to_lra`, we add to the LRA ancoding;
    # here, we support that `forest_to_lra` was invoked with `pure_lra=false`.

    smt_code = replace(smt_code, "Atom{String}: " => "")

    # Write the generated code to the output file
    if output_file isa String
        open(output_file, "w") do f
            write(f, smt_code)
        end

        # println("SMTLIB2 file generated: $output_file")
    end

    return smt_code
end

"""
    collect_symbols!(expr, vars, outputs)

Recursively extracts all input variables (V) and output variables (o) from the expression tree.

This function scans the expression and its children to identify:
- Input variables: Named as V1, V2, V3, etc.
- Output variables: Named as o1, o2, o3, etc. (found in expressions like [o1] == 1.5)

# Arguments
- `expr`: The expression or expression node to scan
- `vars`: A Set{String} that will be populated with input variable names (e.g., "V1", "V2")
- `outputs`: A Set{String} that will be populated with output variable names (e.g., "o1", "o2")

# Regular Expressions Used

## Regex 1: `r"\\bV(\\d+)\\b"`
**Purpose:** Match input variables like V1, V2, V10, V123

**Pattern breakdown:**
- `\\b` = **Word boundary** - Ensures we match complete variable names, not parts of larger words
- `V` = **Literal character 'V'** - The prefix for all input variables
- `(\\d+)` = **Capture group with one or more digits** - Captures the variable index number
- `\\b` = **Word boundary** - Ensures the variable name ends cleanly

**Examples:**
- ✓ Matches: `V1`, `V2`, `V10`, `V123`, `V999`
- ✗ Does NOT match: `VV1` (no word boundary before V), `V` (no digits), `V1x` (character after digits), `MyV1` (word boundary violated)
```julia
# Example matches in strings:
"V1 < 0.5"           # Matches: V1 (captures "1")
"V2 >= 1.0 and V10"  # Matches: V2 (captures "2"), V10 (captures "10")
"MyV3 is V4"         # Matches: V4 only (captures "4"), NOT MyV3
```

## Regex 2: `r"\\[o(\\d+)\\]\\s*==\\s*([\\d.e\\-+]+)"`
**Purpose:** Match output variable assignments like [o1] == 1.5, [o2] == -3.14e-5

**Pattern breakdown:**
- `\\[` = **Literal left bracket** - Opening bracket character
- `o` = **Literal character 'o'** - The prefix for output variables
- `(\\d+)` = **Capture group 1: one or more digits** - Captures the output index number
- `\\]` = **Literal right bracket** - Closing bracket character
- `\\s*` = **Zero or more whitespace characters** - Allows spaces before ==
- `==` = **Literal equality operator** - Two equals signs
- `\\s*` = **Zero or more whitespace characters** - Allows spaces after ==
- `([\\d.e\\-+]+)` = **Capture group 2: numeric value** - Captures the assigned value
  - `\\d` = digits
  - `.` = decimal point
  - `e` = scientific notation exponent
  - `\\-` = minus sign
  - `+` = plus sign
  - `+` (quantifier) = one or more of these characters

**Examples:**
- ✓ Matches:
  - `[o1] == 1.5` → Captures: ("1", "1.5")
  - `[o2]==3.14` → Captures: ("2", "3.14")
  - `[o10] == -2.5e-3` → Captures: ("10", "-2.5e-3")
  - `[o5]  ==  +123.456` → Captures: ("5", "+123.456")
- ✗ Does NOT match:
  - `o1 == 1.5` (missing brackets)
  - `[o1] = 1.5` (single equals)
  - `[o1] == abc` (non-numeric value)
```julia
# Example matches in strings:
"[o1] == 1.881"           # Matches: o1, value 1.881
"[o2]==3.14 and [o3]==0"  # Matches: o2 (3.14), o3 (0)
"[o10] == -1.5e-5"        # Matches: o10, value -1.5e-5
```

# Examples
```julia
vars = Set{String}()
outputs = Set{String}()

# Example 1: Simple expression
expr_str = "V1 < 0.5 and [o1] == 1.0"
collect_symbols!(expr_str, vars, outputs)
# Result: vars = {"V1"}, outputs = {"o1"}

# Example 2: Complex expression
expr_str = "V2 >= 0.687 and V10 < 1.5 and [o3] == -2.5e-3"
collect_symbols!(expr_str, vars, outputs)
# Result: vars = {"V2", "V10"}, outputs = {"o3"}

# Example 3: Nested expression with children
# If expr has children nodes, function recurses through all of them
```
"""
function collect_symbols!(expr, vars, outputs)
    # Convert expression to string for pattern matching
    str = string(expr)

    # Regex 1: Find all input variables (V followed by digits)
    # Pattern: \bV(\d+)\b
    # Matches: V1, V2, V10, V123, etc.
    for m in eachmatch(r"\bV(\d+)\b", str)
        push!(vars, "V$(m.captures[1])")
    end

    # Regex 2: Find all output variables in assignment expressions
    # Pattern: \[o(\d+)\]\s*==\s*([\d.e\-+]+)
    # Matches: [o1] == 1.5, [o2]==-3.14, [o10] == 2.5e-3, etc.
    for m in eachmatch(r"\[o(\d+)\]\s*==\s*([\d.e\-+]+)", str)
        push!(outputs, "o$(m.captures[1])")
    end

    # Recursively process child nodes if they exist
    if hasproperty(expr, :children)
        for child in expr.children
            collect_symbols!(child, vars, outputs)
        end
    end
end

"""
    function generate_smtlib2(
        expr,
        vars,
        outputs;
    )(expr, vars, outputs)

Generates complete SMTLIB2 code from the expression and collected variables.

This function creates a valid SMTLIB2 file with:
- Logic declaration (QF_LIRA = Quantifier-Free Linear Integer Real Arithmetic)
- Variable declarations for inputs and outputs
- Constraint assertions
- Solver commands

# Arguments
- `expr`: The symbolic expression to convert
- `vars`: Set of input variable names (e.g., {"V1", "V2"})
- `outputs`: Set of output variable names (e.g., {"o1", "o2"})

# Keyword Arguments
You can use the following two arguments to add a single, new output variable, such as
`(declare-const Or Real)`.

# Returns
- A string containing the complete SMTLIB2 code

# Examples
```julia
vars = Set(["V1", "V2"])
outputs = Set(["o1"])
expr = "(V1 < 0.5) ∧ ([o1] == 1.0)"

code = generate_smtlib2(expr, vars, outputs)
# Returns:
# ; Auto-generated SMTLIB2 from SyntaxBranch
# (set-logic QF_LIRA)
#
# ; Input variables
# (declare-const V1 Real)
# (declare-const V2 Real)
#
# ; Output variables
# (declare-const o1 Real)
#
# ; Constraints
# (assert
#   (and
#     (< V1 0.5)
#     (= o1 1.0)
#   )
# )
#
# (check-sat)
# (get-model)
```
"""
function generate_smtlib2(
    expr, vars, outputs; integerfeatures=Int[], typeof_output=1
)
    io = IOBuffer()

    # Header comment
    println(io, "; Auto-generated SMTLIB2 from SyntaxBranch")
    println(io, "(set-logic QF_LIRA)")  # Quantifier-Free Nonlinear Real Arithmetic
    println(io)

    # Declare all input variables as Real constants
    println(io, "; Input variables")

    pop_or = nothing
    try
        pop_or = pop!(vars, "Or")
    catch
    end

    for v in sort(collect(vars); by=x -> parse(Int, match(r"\d+", x).match))
        intv = parse(Int, match(r"\d+", v).match)

        println(
            io, "(declare-const $v $(intv in integerfeatures ? "Int" : "Real"))"
        )
    end

    # Declare all output variables as Real constants
    println(io, "; Output variables")
    if !isnothing(pop_or)
        println(io, "(declare-const Or $(typeof_output == 1 ? "Real" : "Int"))")
        push!(vars, "Or") # ingest Or back into pop_or, also if this is useless
    end

    for o in sort(collect(outputs); by=x -> parse(Int, match(r"\d+", x).match))
        println(io, "(declare-const $o Real)")
    end

    println(io)

    # Convert the expression tree to SMTLIB2 assertions
    println(io, "; Constraints")
    println(io, "(assert")
    convert_expr!(io, expr, 1)
    println(io, ")")
    println(io)

    # Add solver commands
    println(io, "(check-sat)")    # Ask solver to check satisfiability
    println(io, "(get-model)")    # Request a model if satisfiable

    return String(take!(io))
end

"""
    convert_expr!(io, expr, indent)

Recursively converts an expression tree to SMTLIB2 format with proper indentation.

This function handles:
- Logical operators: ∧ (and), ∨ (or), → (implies)
- Comparison operators: <, ≥, ==
- Recursive tree traversal with indentation

# Arguments
- `io`: IOBuffer to write the SMTLIB2 code to
- `expr`: The expression node to convert
- `indent`: Current indentation level (number of 2-space indents)

# Examples
```julia
io = IOBuffer()

# Example 1: Simple condition
expr = "V1 < 0.5"
convert_expr!(io, expr, 1)
# Writes: "  (< V1 0.5)\n"

# Example 2: Logical AND
expr = "(V1 < 0.5) ∧ (V2 >= 1.0)"
convert_expr!(io, expr, 1)
# Writes:
# "  (and\n"
# "    (< V1 0.5)\n"
# "    (>= V2 1.0)\n"
# "  )\n"

# Example 3: Nested logic
expr = "(V1 < 0.5) ∧ ((V2 >= 1.0) ∨ ([o1] == 2.0))"
convert_expr!(io, expr, 1)
# Writes:
# "  (and\n"
# "    (< V1 0.5)\n"
# "    (or\n"
# "      (>= V2 1.0)\n"
# "      (= o1 2.0)\n"
# "    )\n"
# "  )\n"
```
"""
function convert_expr!(io, expr, indent)
    # Create indentation string (2 spaces per level)
    ind = "  " ^ indent

    # Check if expression has a logical operator token
    if hasproperty(expr, :token)
        token = string(expr.token)

        # Handle logical AND: ∧
        if token == "∧"
            println(io, ind * "(and")
            for child in expr.children
                convert_expr!(io, child, indent + 1)
            end
            print(io, ind * ")")

            # Handle logical OR: ∨
        elseif token == "∨"
            println(io, ind * "(or")
            for child in expr.children
                convert_expr!(io, child, indent + 1)
            end
            print(io, ind * ")")

            # Handle logical IMPLIES: →
        elseif token == "→"
            println(io, ind * "(=>")
            for child in expr.children
                convert_expr!(io, child, indent + 1)
            end
            print(io, ind * ")")

        elseif token == "¬"
            println(io, ind * "(not")
            for child in expr.children
                convert_expr!(io, child, indent+1)
            end
            print(io, ind * ")")

            # Handle leaf condition (comparison)
        else
            converted = convert_condition(string(expr))
            print(io, ind * converted)
        end
    else
        # No token property, treat as leaf condition
        converted = convert_condition(string(expr))
        converted = replace(converted, r"Atom\{.*\}\: " => "")
        converted = convert_condition(converted)

        print(io, ind * converted)
    end

    println(io)
end

"""
    convert_condition(str)

Converts a single condition string from Julia syntax to SMTLIB2 syntax.

This function handles various comparison operators and variable formats:
- Input variables: V1, V2, etc.
- Output variables: [o1], [o2], etc.
- Operators: <, ≥, >=, ==

# Arguments
- `str`: A condition string in Julia format

# Returns
- The condition converted to SMTLIB2 format

# Regular Expressions Used

## Regex 1: `r"(V\\d+)\\s*<\\s*([\\d.e\\-+]+)"`
**Purpose:** Match less-than comparisons with input variables

**Pattern breakdown:**
- `(V\\d+)` = **Capture group 1: Variable name** - V followed by one or more digits
- `\\s*` = **Zero or more whitespace** - Allows spaces around operator
- `<` = **Literal less-than operator**
- `\\s*` = **Zero or more whitespace**
- `([\\d.e\\-+]+)` = **Capture group 2: Numeric value** - Number with optional decimal, exponent, sign

**Examples:**
- `V2 < 0.687` → `(< V2 0.687)`
- `V10<1.5` → `(< V10 1.5)`
- `V1 < -2.5e-3` → `(< V1 -2.5e-3)`

## Regex 2: `r"(V\\d+)\\s*[≥>=<≤]+\\s*([\\d.e\\-+]+)"`
**Purpose:** Match greater-than-or-equal comparisons with input variables

**Pattern breakdown:**
- `(V\\d+)` = **Capture group 1: Variable name**
- `\\s*` = **Zero or more whitespace**
- `[≥>=<≤]+` = **One or more of ≥, >, or =** - Matches ≥ or >= operators
- `\\s*` = **Zero or more whitespace**
- `([\\d.e\\-+]+)` = **Capture group 2: Numeric value**

**Examples:**
- `V2 ≥ 0.687` → `(>= V2 0.687)`
- `V5>=1.0` → `(>= V5 1.0)`
- `V1 >= -5.5` → `(>= V1 -5.5)`

## Regex 3: `r"\\[o(\\d+)\\]\\s*==\\s*([\\d.e\\-+]+)"`
**Purpose:** Match equality comparisons with output variables

**Pattern breakdown:**
- `\\[` = **Literal left bracket**
- `o` = **Literal 'o'**
- `(\\d+)` = **Capture group 1: Output index**
- `\\]` = **Literal right bracket**
- `\\s*` = **Zero or more whitespace**
- `==` = **Literal equality operator**
- `\\s*` = **Zero or more whitespace**
- `([\\d.e\\-+]+)` = **Capture group 2: Numeric value**

**Examples:**
- `[o1] == 1.881` → `(= o1 1.881)`
- `[o5]==0.5` → `(= o5 0.5)`
- `[o10] == -3.14e-2` → `(= o10 -3.14e-2)`

## Regex 4: `r"\\[o(\\d+)\\]\\s*<\\s*([\\d.e\\-+]+)"`
**Purpose:** Match less-than comparisons with output variables

**Pattern breakdown:**
- Similar to Regex 3, but with `<` instead of `==`

**Examples:**
- `[o1] < 0.5` → `(< o1 0.5)`
- `[o3]<1.0` → `(< o3 1.0)`

## Regex 5: `r"\\[o(\\d+)\\]\\s*[≥>=<≤]+\\s*([\\d.e\\-+]+)"`
**Purpose:** Match greater-than-or-equal comparisons with output variables

**Pattern breakdown:**
- Similar to Regex 3, but with `[≥>=<≤]+` instead of `==`

**Examples:**
- `[o1] ≥ 0.5` → `(>= o1 0.5)`
- `[o2]>=2.0` → `(>= o2 2.0)`

# Examples
```julia
# Input variable comparisons
convert_condition("V2 < 0.687")
# Returns: "(< V2 0.687)"

convert_condition("V5 ≥ 1.234")
# Returns: "(>= V5 1.234)"

convert_condition("V10 >= -2.5e-3")
# Returns: "(>= V10 -2.5e-3)"

# Output variable comparisons
convert_condition("[o1] == 1.881")
# Returns: "(= o1 1.881)"

convert_condition("[o3] < 0.5")
# Returns: "(< o3 0.5)"

convert_condition("[o2] ≥ 2.0")
# Returns: "(>= o2 2.0)"

# Strips SyntaxBranch prefix if present
convert_condition("SyntaxBranch: V1 < 0.5")
# Returns: "(< V1 0.5)"
```
"""
function convert_condition(str)

    # TODO
    # The patterns below could be refactored in something similar to
    # for _rels in [>=, <=, =]
    #     m = match(r"(V\d+)\s*[$(_rels)]+\s*([\d.e\-+]+)", str)
    #     if m !== nothing
    #         v = Printf.format(Printf.Format("%.16f"), parse(Float64, m.captures[2]))
    #         v = rstrip(rstrip(v, '0'), '.')
    #         return "(>= $(m.captures[1]) $(v))"
    #     end
    # end

    # Strip leading/trailing whitespace
    str = strip(str)

    # Remove "SyntaxBranch:" prefix if present
    str = replace(str, r"^SyntaxBranch:\s*" => "")

    # Pattern 1: V2 < 0.687 → (< V2 0.687)
    # Matches: Variable less-than number
    m = match(r"(V\d+)\s*<\s*([\d.e\-+]+)", str)
    if m !== nothing
        v = Printf.format(Printf.Format("%.16f"), parse(Float64, m.captures[2]))
        v = rstrip(rstrip(v, '0'), '.')
        return "(< $(m.captures[1]) $(v))"
    end

    # Pattern 2: V2 ≥ 0.687 or V2 >= 0.687 → (>= V2 0.687)
    # Matches: Variable greater-than-or-equal number
    m = match(r"(V\d+)\s*[≥>=]+\s*([\d.e\-+]+)", str)
    if m !== nothing
        v = Printf.format(Printf.Format("%.16f"), parse(Float64, m.captures[2]))
        v = rstrip(rstrip(v, '0'), '.')
        return "(>= $(m.captures[1]) $(v))"
    end

    # Pattern 2.2
    m = match(r"(V\d+)\s*[≤<=]+\s*([\d.e\-+]+)", str)
    if m !== nothing
        v = Printf.format(Printf.Format("%.16f"), parse(Float64, m.captures[2]))
        v = rstrip(rstrip(v, '0'), '.')
        return "(<= $(m.captures[1]) $(v))"
    end

    # Pattern 3: [o1] == 1.881 → (= o1 1.881)
    # Matches: Output variable equals number
    m = match(r"\[o(\d+)\]\s*==\s*([\d.e\-+]+)", str)
    if m !== nothing
        v = Printf.format(Printf.Format("%.16f"), parse(Float64, m.captures[2]))
        v = rstrip(rstrip(v, '0'), '.')
        return "(= o$(m.captures[1]) $(v))"
    end

    # Pattern 4: [o1] < 0.5 → (< o1 0.5)
    # Matches: Output variable less-than number
    m = match(r"\[V(\d+)\]\s*<\s*([\d.e\-+]+)", str)
    if m !== nothing
        v = Printf.format(Printf.Format("%.16f"), parse(Float64, m.captures[2]))
        v = rstrip(rstrip(v, '0'), '.')
        return "(< V$(m.captures[1]) $(v))"
    end

    # Pattern 5
    # Matches: Output variable greater-than-or-equal number
    m = match(r"\[V(\d+)\]\s*[≥>=]+\s*([\d.e\-+]+)", str)
    if m !== nothing
        v = Printf.format(Printf.Format("%.16f"), parse(Float64, m.captures[2]))
        v = rstrip(rstrip(v, '0'), '.')
        return "(>= V$(m.captures[1]) $(v))"
    end

    m = match(r"\[V(\d+)\]\s*[≤<=]+\s*([\d.e\-+]+)", str)
    if m !== nothing
        v = Printf.format(Printf.Format("%.16f"), parse(Float64, m.captures[2]))
        v = rstrip(rstrip(v, '0'), '.')
        return "(<= V$(m.captures[1]) $(v))"
    end

    # Pattern 6
    m = match(r"\[Or\]\s*[≥>=]+\s*([\d.e\-+]+)", str)
    if m !== nothing
        v = Printf.format(Printf.Format("%.16f"), parse(Float64, m.captures[1]))
        v = rstrip(rstrip(v, '0'), '.')
        return "(>= Or $(v))"
    end

    # Pattern 7
    m = match(r"\[Or\]\s*[≤<=]+\s*([\d.e\-+]+)", str)
    if m !== nothing
        v = Printf.format(Printf.Format("%.16f"), parse(Float64, m.captures[1]))
        v = rstrip(rstrip(v, '0'), '.')
        return "(<= Or $(v))"
    end

    # Pattern 8
    m = match(r"\[(o\d+)\]\s*>\s*([\d.e\-+]+)", str)
    if m !== nothing
        v = Printf.format(Printf.Format("%.16f"), parse(Float64, m.captures[2]))
        v = rstrip(rstrip(v, '0'), '.')
        return "(> $(m.captures[1]) $(v))"
    end

    # Pattern 9
    m = match(r"\[(o\d+)\]\s*<\s*([\d.e\-+]+)", str)
    if m !== nothing
        v = Printf.format(Printf.Format("%.16f"), parse(Float64, m.captures[2]))
        v = rstrip(rstrip(v, '0'), '.')
        return "(< $(m.captures[1]) $(v))"
    end

    # Pattern 10
    m = match(r"\[(o\d+)\]\s*[≥>=]+\s*([\d.e\-+]+)", str)
    if m !== nothing
        v = Printf.format(Printf.Format("%.16f"), parse(Float64, m.captures[2]))
        v = rstrip(rstrip(v, '0'), '.')
        return "(>= $(m.captures[1]) $(v))"
    end

    # Pattern 11
    m = match(r"\[(o\d+)\]\s*[≤<=]+\s*([\d.e\-+]+)", str)
    if m !== nothing
        v = Printf.format(Printf.Format("%.16f"), parse(Float64, m.captures[2]))
        v = rstrip(rstrip(v, '0'), '.')
        return "(<= $(m.captures[1]) $(v))"
    end

    # If no pattern matches, return original string
    return str
end

"""
Parse the model returned from z3.
See the Examples section.

# Examples
julia> model = "sat\n(\n  (define-fun V2 () Real\n    (- 1.0))\n  (define-fun o2 () Real\n    (/ 3.0 2.0))\n  (define-fun o5 () Real\n    (/ 49119922271227057.0 100000000000000000.0))\n  (define-fun o4 () Real\n    (/ 1.0 4.0))\n  (define-fun V4 () Real\n    (/ 45.0 128.0))\n  (define-fun V1 () Real\n    (/ 3.0 4.0))\n  (define-fun o1 () Real\n    (/ 1.0 2.0))\n  (define-fun V5 () Real\n    (- (/ 50880077728772943.0 100000000000000000.0)))\n)\n"


Returns something like:
"V2 = -1.0"
"o2 = 3.0 / 2.0"
"o5 = 49119922271227057.0 / 100000000000000000.0"
"o4 = 1.0 / 4.0"
"V4 = 45.0 / 128.0"
"V1 = 3.0 / 4.0"
"o1 = 1.0 / 2.0"
"V5 = -(50880077728772943.0 / 100000000000000000.0)"

where each entry is exactly a string.
"""
function parse_z3_model(model_str::String)
    model_str = split(model_str, "\n")[3:end]

    # "V2 = -1.0" or "V4 = 45.0 / 128.0"
    vs = String[]
    # similar as above, but "o2 = 3.0 / 2.0"
    os = String[]

    for (s, v) in zip(model_str[1:2:end], model_str[2:2:end])
        if length(s) <= 1
            continue
        end

        s = split(s, "define-fun ")[2]
        s = split(s, " ")[1]

        v = replace(v, "(" => " ")
        v = replace(v, ")" => " ")
        v = strip(v)

        # handle fractions (including negative fractions)
        # matches patterns like "/ num denom" or "- / num denom"
        m = match(r"^-?\s*\/\s*([\d.]+)\s+([\d.]+)", v)
        if m !== nothing
            numerator = parse(Float64, m.captures[1])
            denominator = parse(Float64, m.captures[2])
            result = numerator / denominator

            # if the original had a minus sign, negate the result
            if startswith(strip(v), "-")
                result = -result
            end

            v = string(result)
        end

        if s[1] == 'V'
            push!(vs, "$(s) = $(v)")
        else
            push!(os, "$(s) = $(v)")
        end
    end

    # we want all the Vs to be sorted
    sort!(vs; by=x -> parse(Int, match(r"V(\d+)", x).captures[1]))

    return vs, os
end
