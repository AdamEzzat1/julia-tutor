csv(rows...) = IOBuffer(join(["site,time,temp,unit,humidity"; collect(rows)], "\n") * "\n")

@testset "reading" begin
    df = read_readings(csv("n,2026-01-02 03:45,7,C,NA", "s,2026-01-02 04:00,-,F,", "e,2026-01-02 05:00,NA,C,-"))
    @test eltype(df.site) == String
    @test eltype(df.time) == DateTime
    @test df.time[1] == DateTime(2026, 1, 2, 3, 45)
    @test nonmissingtype(eltype(df.temp)) == Float64
    @test nonmissingtype(eltype(df.humidity)) == Float64
    @test all(ismissing, df.temp[2:3])
    @test all(ismissing, df.humidity)
    @test_logs min_level = Logging.Warn read_readings(csv("n,2026-01-02 03:45,7,C,NA", "s,2026-01-02 04:00,-,F,"))
    whole = read_readings(csv("n,2026-01-02 03:45,7,C,8"))
    @test nonmissingtype(eltype(whole.humidity)) == Float64
    @test nonmissingtype(eltype(whole.temp)) == Float64
    f = tempname()
    write(f, "site,time,temp,unit,humidity\nn,2026-01-02 03:45,7,C,-\n")
    @test isequal(read_readings(f), read_readings(csv("n,2026-01-02 03:45,7,C,-")))
end
