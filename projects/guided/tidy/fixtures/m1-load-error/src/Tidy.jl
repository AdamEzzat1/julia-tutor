module Tidy

using CSV, DataFrames, Dates

export read_readings

function read_readings(io::IO)
    return CSV.read(io, DataFrame; missingstring = ["NA", "-", ""], dateformat = "yyyy-mm-dd HH:MM",
                    types = Dict(:temp => Float64, :humidity => Float64), stringtype = String)
end

read_readings(path::AbstractString) = open(read_readings, path)

# A typo: `DataFrame` misspelled, so the module fails while it loads.
const EMPTY = DataFrme()

end
