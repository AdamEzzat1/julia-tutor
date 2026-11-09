# A small JSON writer and reader, so the tutor stays stdlib-only.
#
# Writer: deterministic (sorted keys, fixed indentation) because generated files
# are committed and compared byte for byte.
# Reader: used on HTTP request bodies from the local sandbox server, so it is an
# input boundary: it rejects trailing garbage, limits nesting depth and never
# evaluates anything.

module JSON

export to_json, to_json_compact, parse_json, JSONError

# ---- writer --------------------------------------------------------------------

function json_string(io::IO, s::AbstractString)
    print(io, '"')
    for c in s
        if c == '"';      print(io, "\\\"")
        elseif c == '\\'; print(io, "\\\\")
        elseif c == '\n'; print(io, "\\n")
        elseif c == '\r'; print(io, "\\r")
        elseif c == '\t'; print(io, "\\t")
        elseif c < ' ';   print(io, "\\u", lpad(string(UInt32(c), base = 16), 4, '0'))
        elseif !isvalid(c); print(io, "�")
        else              print(io, c)
        end
    end
    print(io, '"')
end

# `d` is the indentation depth, or -1 for compact output.
nl(io, d) = d >= 0 && print(io, "\n", "  "^d)

write_json(io::IO, x::AbstractString, _) = json_string(io, x)
write_json(io::IO, x::Bool, _) = print(io, x ? "true" : "false")
write_json(io::IO, x::Integer, _) = print(io, x)
write_json(io::IO, x::AbstractFloat, _) = isfinite(x) ? print(io, repr(Float64(x))) : print(io, "null")
write_json(io::IO, ::Nothing, _) = print(io, "null")
write_json(io::IO, x::Symbol, d) = write_json(io, String(x), d)
function write_json(io::IO, x::Union{AbstractVector,Tuple}, d)
    isempty(x) && return print(io, "[]")
    print(io, "[")
    for (i, v) in enumerate(x)
        nl(io, d < 0 ? d : d + 1); write_json(io, v, d < 0 ? d : d + 1)
        i < length(x) && print(io, ",")
    end
    nl(io, d); print(io, "]")
end
function write_json(io::IO, x::AbstractDict, d)
    isempty(x) && return print(io, "{}")
    ks = sort!([string(k) for k in keys(x)])
    vals = Dict(string(k) => v for (k, v) in x)
    print(io, "{")
    for (i, k) in enumerate(ks)
        nl(io, d < 0 ? d : d + 1); json_string(io, k); print(io, d < 0 ? ":" : ": ")
        write_json(io, vals[k], d < 0 ? d : d + 1)
        i < length(ks) && print(io, ",")
    end
    nl(io, d); print(io, "}")
end

"""Pretty, deterministic JSON with a trailing newline (for committed files)."""
to_json(x) = (io = IOBuffer(); write_json(io, x, 0); println(io); String(take!(io)))
"""Compact JSON (for HTTP responses)."""
to_json_compact(x) = (io = IOBuffer(); write_json(io, x, -1); String(take!(io)))

# ---- reader --------------------------------------------------------------------

struct JSONError <: Exception
    msg::String
end
Base.showerror(io::IO, e::JSONError) = print(io, "invalid JSON: ", e.msg)

mutable struct Reader
    s::String
    i::Int
    depth::Int
end

const MAX_DEPTH = 64

function skipws(r::Reader)
    while r.i <= ncodeunits(r.s) && r.s[r.i] in (' ', '\t', '\n', '\r')
        r.i = nextind(r.s, r.i)
    end
end
peekc(r::Reader) = r.i <= ncodeunits(r.s) ? r.s[r.i] : '\0'
function expect(r::Reader, c::Char)
    peekc(r) == c || throw(JSONError("expected '$c' at byte $(r.i)"))
    r.i = nextind(r.s, r.i)
end

function read_value(r::Reader)
    skipws(r)
    c = peekc(r)
    if c == '{'
        return read_object(r)
    elseif c == '['
        return read_array(r)
    elseif c == '"'
        return read_string(r)
    elseif c == 't'
        startswith(SubString(r.s, r.i), "true") || throw(JSONError("bad literal at byte $(r.i)"))
        r.i += 4; return true
    elseif c == 'f'
        startswith(SubString(r.s, r.i), "false") || throw(JSONError("bad literal at byte $(r.i)"))
        r.i += 5; return false
    elseif c == 'n'
        startswith(SubString(r.s, r.i), "null") || throw(JSONError("bad literal at byte $(r.i)"))
        r.i += 4; return nothing
    elseif c == '-' || isdigit(c)
        return read_number(r)
    end
    throw(JSONError(c == '\0' ? "unexpected end of input" : "unexpected '$c' at byte $(r.i)"))
end

function nest(f, r::Reader)
    r.depth += 1
    r.depth > MAX_DEPTH && throw(JSONError("nested deeper than $MAX_DEPTH"))
    v = f()
    r.depth -= 1
    return v
end

read_object(r::Reader) = nest(r) do
    expect(r, '{')
    d = Dict{String,Any}()
    skipws(r)
    peekc(r) == '}' && (expect(r, '}'); return d)
    while true
        skipws(r)
        k = read_string(r)
        skipws(r); expect(r, ':')
        d[k] = read_value(r)
        skipws(r)
        peekc(r) == ',' ? expect(r, ',') : (expect(r, '}'); return d)
    end
end

read_array(r::Reader) = nest(r) do
    expect(r, '[')
    v = Any[]
    skipws(r)
    peekc(r) == ']' && (expect(r, ']'); return v)
    while true
        push!(v, read_value(r))
        skipws(r)
        peekc(r) == ',' ? expect(r, ',') : (expect(r, ']'); return v)
    end
end

function read_string(r::Reader)
    expect(r, '"')
    io = IOBuffer()
    while true
        r.i > ncodeunits(r.s) && throw(JSONError("unterminated string"))
        c = r.s[r.i]
        r.i = nextind(r.s, r.i)
        if c == '"'
            return String(take!(io))
        elseif c == '\\'
            e = peekc(r); r.i = nextind(r.s, r.i)
            if e == 'u'
                u = read_hex4(r)
                if 0xd800 <= u <= 0xdbff && startswith(SubString(r.s, r.i), "\\u")
                    r.i += 2
                    lo = read_hex4(r)
                    0xdc00 <= lo <= 0xdfff || throw(JSONError("bad surrogate pair"))
                    print(io, Char(0x10000 + ((u - 0xd800) << 10) + (lo - 0xdc00)))
                else
                    print(io, (0xd800 <= u <= 0xdfff) ? '�' : Char(u))
                end
            else
                m = Dict('"' => '"', '\\' => '\\', '/' => '/', 'b' => '\b', 'f' => '\f',
                         'n' => '\n', 'r' => '\r', 't' => '\t')
                haskey(m, e) || throw(JSONError("bad escape \\$e"))
                print(io, m[e])
            end
        elseif c < ' '
            throw(JSONError("control character in string"))
        else
            print(io, c)
        end
    end
end

function read_hex4(r::Reader)
    r.i + 3 <= ncodeunits(r.s) || throw(JSONError("short \\u escape"))
    h = tryparse(UInt32, r.s[r.i:r.i+3]; base = 16)
    h === nothing && throw(JSONError("bad \\u escape"))
    r.i += 4
    return h
end

function read_number(r::Reader)
    j = r.i
    while r.i <= ncodeunits(r.s) && r.s[r.i] in "+-0123456789.eE"
        r.i += 1
    end
    t = r.s[j:r.i-1]
    v = occursin(r"^-?(0|[1-9][0-9]*)$", t) ? tryparse(Int, t) : nothing
    v === nothing && occursin(r"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$", t) && (v = tryparse(Float64, t))
    v === nothing && throw(JSONError("bad number '$t'"))
    return v
end

"""Parse a JSON document. Throws `JSONError` on malformed input or trailing data."""
function parse_json(s::AbstractString)
    r = Reader(String(s), 1, 0)
    isvalid(r.s) || throw(JSONError("not valid UTF-8"))
    v = read_value(r)
    skipws(r)
    r.i <= ncodeunits(r.s) && throw(JSONError("trailing data at byte $(r.i)"))
    return v
end

end # module JSON
