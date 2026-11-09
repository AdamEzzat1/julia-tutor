# Exemplary student tests, milestone 4: write_summary and read_summary.
using DataFrames, Dates

@testset "write and read back" begin
    s = DataFrame(site = ["a"], date = [Date(2026, 3, 1)], n = [2], mean_temp = [1.006], max_temp = [2.5],
                  mean_humidity = Union{Missing,Float64}[missing])
    io = IOBuffer()
    write_summary(io, s)
    text = String(take!(io))
    @test text == "site,date,n,mean_temp,max_temp,mean_humidity\na,2026-03-01,2,1.01,2.5,NA\n"
    back = read_summary(IOBuffer(text))
    @test back.site == ["a"]
    @test eltype(back.site) == String
    @test back.date == s.date
    @test back.mean_temp[1] ≈ 1.01 rtol = 1e-15     # parsed from "1.01": the nearest Float64
    @test ismissing(back.mean_humidity[1])
end
