# Acceptance, milestone 4: write_summary and read_summary. One @testset per behaviour id.
#
# Round-trip tolerance: a value written with 2 decimals and parsed back is the
# Float64 nearest to the decimal, so it differs from round(x; digits = 2) by
# at most half an ulp: rtol = 1e-15 (about 4.5 eps) bounds that.
using Tidy, Test, DataFrames, Dates

summary_frame() = DataFrame(site = ["east", "north"], date = [Date(2026, 3, 1), Date(2026, 3, 2)], n = [3, 1],
                            mean_temp = [12.3456, 3.0], max_temp = [14.5, 3.0],
                            mean_humidity = Union{Missing,Float64}[61.0 / 3, missing])

written() = (io = IOBuffer(); write_summary(io, summary_frame()); String(take!(io)))

@testset "missing-as-NA" begin
    lines = split(chomp(written()), '\n')
    @test lines[1] == "site,date,n,mean_temp,max_temp,mean_humidity"
    @test endswith(lines[3], ",NA")
    @test occursin("2026-03-02", lines[3])
end

@testset "rounding" begin
    lines = split(chomp(written()), '\n')
    @test occursin(",12.35,", lines[2])
    @test endswith(lines[2], ",20.33")
end

@testset "round-trip" begin
    back = read_summary(IOBuffer(written()))
    s = summary_frame()
    @test names(back) == names(s)
    @test back.site == s.site && eltype(back.site) === String
    @test back.date == s.date
    @test back.n == s.n && eltype(back.n) === Int
    @test isapprox(back.mean_temp, round.(s.mean_temp; digits = 2); rtol = 1e-15)
    @test ismissing(back.mean_humidity[2])
    @test isapprox(back.mean_humidity[1], 20.33; rtol = 1e-15)
    @test nonmissingtype(eltype(back.mean_humidity)) === Float64
end
