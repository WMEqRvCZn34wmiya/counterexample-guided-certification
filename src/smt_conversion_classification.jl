"""
    to_smtlib2_classification(expr; output_file = "output.smt2")

Extended to handle forest LRA encoding with proper type declarations.
"""
function to_smtlib2_classification(
    expr;
    output_file::Union{Nothing,String}=nothing,
    force_input=String[],
    force_output=String[],
    integerfeatures=Int[],
    typeof_output=1,
    kwargs...,
)
    vars = Set{String}()
    outputs = Set{String}()
    indicator_vars = Set{String}()  # o_i_j variables
    count_vars = Set{String}()      # c_j variables
    event_vars = Set{String}()      # e_j variables
    z_var_ref = Ref(false)          # z variable flag

    collect_symbols_classification!(
        expr, vars, outputs, indicator_vars, count_vars, event_vars, z_var_ref
    )

    for fi in force_input
        push!(vars, fi)
    end

    for fo in force_output
        push!(outputs, fo)
    end

    smt_code = generate_smtlib2_classification(
        expr,
        vars,
        outputs,
        indicator_vars,
        count_vars,
        event_vars,
        z_var_ref[];
        integerfeatures,
        typeof_output,
        kwargs...,
    )

    smt_code = replace(smt_code, "Atom{String}: " => "")

    if output_file isa String
        open(output_file, "w") do f
            write(f, smt_code)
        end
    end

    return smt_code
end

"""
    collect_symbols_classification!(expr, vars, outputs, indicator_vars, count_vars, event_vars, z_var)

Extended to collect all variable types from forest encoding.
"""
function collect_symbols_classification!(
    expr, vars, outputs, indicator_vars, count_vars, event_vars, z_var_ref
)
    # previous version
    # str = string(expr)
    # WARNING: this could be the cause of many bugs; probably, other calls to 
    # `string` in this file must be changed
    str = SoleLogics.syntaxstring(expr; parenthesize_atoms=true)

    # Input variables V1, V2, etc. (Real)
    for m in eachmatch(r"\bV(\d+)\b", str)
        push!(vars, "V$(m.captures[1])")
    end

    # Output variables o1, o2, etc. (Int in forest encoding)
    for m in eachmatch(r"\[o(\d+)\]", str)
        push!(outputs, "o$(m.captures[1])")
    end

    # Indicator variables o_i_j (Int/Boolean represented as 0/1)
    for m in eachmatch(r"\[o(\d+)_(\d+)\]", str)
        push!(indicator_vars, "o$(m.captures[1])_$(m.captures[2])")
    end

    # Count variables c1, c2, c3, etc. (Int)
    for m in eachmatch(r"\[c(\d+)\]", str)
        push!(count_vars, "c$(m.captures[1])")
    end

    # Event variables e1, e2, e3, etc. (Boolean)
    for m in eachmatch(r"\be(\d+)\b", str)
        push!(event_vars, "e$(m.captures[1])")
    end

    # Z variable (Int) - use Ref to modify boolean
    if occursin(r"\bz\b", str)
        z_var_ref[] = true
    end

    # Or variable is handled separately in outputs

    if hasproperty(expr, :children)
        for child in expr.children
            collect_symbols_classification!(
                child,
                vars,
                outputs,
                indicator_vars,
                count_vars,
                event_vars,
                z_var_ref,
            )
        end
    end
end

"""
    generate_smtlib2_classification(expr, vars, outputs, indicator_vars, count_vars, event_vars, z_var)

Extended to declare all variable types correctly.
"""
function generate_smtlib2_classification(
    expr,
    vars,
    outputs,
    indicator_vars,
    count_vars,
    event_vars,
    z_var;
    integerfeatures=Int[],
    typeof_output=1,
)
    io = IOBuffer()

    println(
        io, "; Auto-generated SMTLIB2 from SyntaxBranch with Forest Encoding"
    )
    println(io, "(set-logic QF_LIRA)")
    println(io)

    # Input variables (Real or Int based on integerfeatures)
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
    println(io)

    # Output variables (Int for forest encoding)
    println(io, "; Output variables (Int for classification)")
    for o in sort(collect(outputs); by=x -> parse(Int, match(r"\d+", x).match))
        println(io, "(declare-const $o Int)")
    end
    println(io)

    # Or variable (Int)
    println(io, "; Or variable (final prediction, Int)")
    println(io, "(declare-const Or Int)")
    push!(vars, "Or")
    println(io)

    # Indicator variables o_i_j (Int, representing Boolean 0/1)
    if !isempty(indicator_vars)
        println(io, "; Indicator variables o_i_j (Int as Boolean 0/1)")
        for ov in sort(
            collect(indicator_vars);
            by=x -> begin
                m = match(r"o(\d+)_(\d+)", x)
                (parse(Int, m.captures[1]), parse(Int, m.captures[2]))
            end,
        )
            println(io, "(declare-const $ov Int)")
        end
        println(io)
    end

    # Count variables c_j (Int)
    if !isempty(count_vars)
        println(io, "; Count variables c_j (Int)")
        for cv in sort(
            collect(count_vars); by=x -> parse(Int, match(r"\d+", x).match)
        )
            println(io, "(declare-const $cv Int)")
        end
        println(io)
    end

    # Event variables e_j (Bool)
    if !isempty(event_vars)
        println(io, "; Event variables e_j (Bool)")
        for ev in sort(
            collect(event_vars); by=x -> parse(Int, match(r"\d+", x).match)
        )
            println(io, "(declare-const $ev Bool)")
        end
        println(io)
    end

    # Z variable (Int)
    if z_var
        println(io, "; Z variable (maximum count, Int)")
        println(io, "(declare-const z Int)")
        println(io)
    end

    # Constraints
    println(io, "; Constraints")
    println(io, "(assert")
    convert_expr_classification!(io, expr, 1)
    println(io, ")")
    println(io)

    println(io, "(check-sat)")
    println(io, "(get-model)")

    return String(take!(io))
end

"""
    convert_expr_classification!(io, expr, indent)

Extended to handle negation (¬) operator.
"""
function convert_expr_classification!(io, expr, indent)
    ind = "  " ^ indent

    if hasproperty(expr, :token)
        token = string(expr.token)

        if token == "∧"
            println(io, ind * "(and")
            for child in expr.children
                convert_expr_classification!(io, child, indent + 1)
            end
            print(io, ind * ")")

        elseif token == "∨"
            println(io, ind * "(or")
            for child in expr.children
                convert_expr_classification!(io, child, indent + 1)
            end
            print(io, ind * ")")

        elseif token == "→"
            println(io, ind * "(=>")
            for child in expr.children
                convert_expr_classification!(io, child, indent + 1)
            end
            print(io, ind * ")")

        elseif token == "¬"
            println(io, ind * "(not")
            for child in expr.children
                convert_expr_classification!(io, child, indent + 1)
            end
            print(io, ind * ")")

        else
            converted = convert_condition_classification(string(expr))
            print(io, ind * converted)
        end
    else
        converted = convert_condition_classification(string(expr))
        converted = replace(converted, r"Atom\{.*\}\: " => "")
        converted = convert_condition_classification(converted)
        print(io, ind * converted)
    end

    println(io)
end

"""
    convert_condition_classification(str)

Extended to handle all variable patterns in forest encoding.
"""
function convert_condition_classification(str)
    str = strip(str)
    str = replace(str, r"^SyntaxBranch:\s*" => "")

    # Helper function for float formatting
    format_float =
        (s) -> begin
            v = Printf.format(Printf.Format("%.16f"), parse(Float64, s))
            rstrip(rstrip(v, '0'), '.')
        end

    # Pattern: V variables with comparison operators
    for (op_pattern, op_smtlib) in
        [(r"<", "<"), (r"[≥>=]+", ">="), (r"[≤<=]+", "<="), (r"==", "=")]
        m = match(Regex("(V\\d+)\\s*$(op_pattern)\\s*([\\d.e\\-+]+)"), str)
        if m !== nothing
            return "($(op_smtlib) $(m.captures[1]) $(format_float(m.captures[2])))"
        end
    end

    # Pattern: [V_i] variables
    for (op_pattern, op_smtlib) in
        [("<", "<"), ("[≥>=]+", ">="), ("[≤<=]+", "<="), ("==", "=")]
        m = match(Regex("V(\\d+)\\s*$op_pattern\\s*([\\d.e\\-+]+)"), str)
        if m !== nothing
            return "($(op_smtlib) V$(m.captures[1]) $(format_float(m.captures[2])))"
        end
    end

    # Pattern: [o_i] output variables
    for (op_pattern, op_smtlib) in [
        (">", ">"),
        ("<", "<"),
        (">=", ">="),
        (">", ">"),
        ("=", "="),
        ("≥", ">="),
        ("≤", "<="),
        ("<=", "<="),
        ("==", "="),
    ]
        m = match(
            Regex("\\[(o\\d+)\\]\\s*($(op_pattern))\\s*([\\d.e\\-+]+)"), str
        )

        if m !== nothing
            return "($(op_smtlib) $(m.captures[1]) $(format_float(m.captures[3])))"
        end
    end

    # Pattern: [o_i_j] indicator variables
    for (op_pattern, op_smtlib) in [
        (">", ">"),
        ("<", "<"),
        (">=", ">="),
        (">", ">"),
        ("=", "="),
        ("≥", ">="),
        ("≤", "<="),
        ("<=", "<="),
        ("==", "="),
    ]
        m = match(
            Regex("\\[(o\\d+_\\d+)\\]\\s*$(op_pattern)\\s*([\\d.e\\-+]+)"), str
        )
        if m !== nothing
            return "($(op_smtlib) $(m.captures[1]) $(format_float(m.captures[2])))"
        end
    end

    # Pattern: [c_j] count variables
    for (op_pattern, op_smtlib) in [
        (">", ">"),
        ("<", "<"),
        (">=", ">="),
        (">", ">"),
        ("=", "="),
        ("≥", ">="),
        ("≤", "<="),
        ("<=", "<="),
        ("==", "="),
    ]
        m = match(Regex("c(\\d+)\\s*$(op_pattern)\\s*([\\d.e\\-+]+)"), str)
        if m !== nothing
            return "($(op_smtlib) c$(m.captures[1]) $(format_float(m.captures[2])))"
        end
    end

    # Pattern: [Or] variable
    for (op_pattern, op_smtlib) in [
        (">", ">"),
        ("<", "<"),
        (">=", ">="),
        (">", ">"),
        ("=", "="),
        ("≥", ">="),
        ("≤", "<="),
        ("<=", "<="),
        ("==", "="),
    ]
        m = match(Regex("Or\\s*$(op_pattern)\\s*([\\d.e\\-+]+)"), str)
        if m !== nothing
            return "($(op_smtlib) Or $(format_float(m.captures[1])))"
        end
    end

    for (op_pattern, op_smtlib) in [
        (">", ">"),
        ("<", "<"),
        (">=", ">="),
        (">", ">"),
        ("=", "="),
        ("≥", ">="),
        ("≤", "<="),
        ("<=", "<="),
        ("==", "="),
    ]
        m = match(Regex("\\[Or\\]\\s*$(op_pattern)\\s*([\\d.e\\-+]+)"), str)
        if m !== nothing
            return "($(op_smtlib) Or $(format_float(m.captures[1])))"
        end
    end

    # Pattern: z variable comparisons
    for (op_pattern, op_smtlib) in [
        (">", ">"),
        ("<", "<"),
        (">=", ">="),
        (">", ">"),
        ("=", "="),
        ("≥", ">="),
        ("≤", "<="),
        ("<=", "<="),
        ("==", "="),
    ]
        # z compared to number: z >= 5
        m = match(Regex("\\bz\\s*$(op_pattern)\\s*([\\d.e\\-+]+)"), str)
        if m !== nothing
            return "($(op_smtlib) z $(format_float(m.captures[1])))"
        end

        # z compared to c_j: z >= c_1 or z == c_1
        m = match(Regex("\\bz\\s*$(op_pattern)\\s*c_(\\d+)\\b"), str)
        if m !== nothing
            return "($(op_smtlib) z c$(m.captures[1]))"
        end

        # c_j compared to z: c1 == z
        m = match(Regex("\\bc(\\d+)\\s*$(op_pattern)\\s*z\\b"), str)
        if m !== nothing
            return "($(op_smtlib) c$(m.captures[1]) z)"
        end
    end

    # Pattern: arithmetic expressions like [c1] == o1_1 + o2_1 + ...
    m = match(r"\[c(\d+)\]\s*==\s*(.+)", str)
    if m !== nothing
        sum_expr = strip(m.captures[2])
        # Convert addition to SMTLIB2 format
        terms = split(sum_expr, r"\s*\+\s*")
        if length(terms) > 1
            smtlib_sum = "(+ " * join(terms, " ") * ")"
            return "(= c$(m.captures[1]) $smtlib_sum)"
        end
    end

    # Pattern: e_j variables (Boolean)
    m = match(r"\be(\d+)\b", str)
    if m !== nothing
        return "e$(m.captures[1])"
    end

    return str
end

"""
    parse_z3_model_classification(model_str::String)

Parse Z3 model output into separate variable assignments.
"""
function parse_z3_model_classification(model_str::String)
    model_str = split(model_str, "\n")[3:end]

    vs = String[]
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

        if v[1] == '/'
            m = match(r"\/ ([\d.]+) ([\d.]+)", v)
            v = eval(Meta.parse("($(m.captures[1]) / $(m.captures[2]))"))
        end

        if s[1] == 'V'
            push!(vs, "$(s) = $(v)")
        else
            push!(os, "$(s) = $(v)")
        end
    end

    sort!(vs; by=x -> parse(Int, match(r"V(\d+)", x).captures[1]))

    return vs, os
end
