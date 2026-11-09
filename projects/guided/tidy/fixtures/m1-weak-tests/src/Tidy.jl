# A student's milestone 1, in another style than the reference: keyword
# arguments built inline, and an explicit conversion afterwards instead of
# forcing the number types in CSV.read.
module Tidy

using CSV
using DataFrames
using Dates

export read_readings

function read_readings(io::IO)
    df = CSV.read(io, DataFrame;
                  missingstring = ["NA", "-", ""],
                  dateformat = "yyyy-mm-dd HH:MM",
                  types = Dict(:time => DateTime),
                  stringtype = String)
    for col in (:temp, :humidity)
        df[!, col] = convert(Vector{Union{Missing,Float64}}, df[!, col])
    end
    return df
end

function read_readings(path::AbstractString)
    open(path) do io
        read_readings(io)
    end
end

end
