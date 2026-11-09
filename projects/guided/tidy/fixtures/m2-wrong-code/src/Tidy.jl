module Tidy

using CSV, DataFrames, Dates

export read_readings, clean

function read_readings(io::IO)
    return CSV.read(io, DataFrame; missingstring = ["NA", "-", ""], dateformat = "yyyy-mm-dd HH:MM",
                    types = Dict(:temp => Float64, :humidity => Float64), stringtype = String)
end

read_readings(path::AbstractString) = open(read_readings, path)

ok(t, h) = !ismissing(t) && -50 <= t <= 60 && (ismissing(h) || 0 <= h <= 100)

function clean(df::DataFrame)
    out = copy(df)
    out.site = lowercase.(strip.(out.site))
    for i in eachindex(out.temp)
        if out.unit[i] == "F"
            out.temp[i] = (out.temp[i] - 32) * 9 / 5     # the bug: the ratio is upside down
            out.unit[i] = "C"
        end
    end
    unique!(out)
    out.valid = ok.(out.temp, out.humidity)
    return out
end

end
