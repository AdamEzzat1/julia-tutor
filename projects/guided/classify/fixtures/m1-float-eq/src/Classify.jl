module Classify

using Random

export load_split

function read_file(path)
    labels = String[]
    values = Float32[]
    nfeat = 0
    for (i, line) in enumerate(eachline(path))
        i == 1 && continue                  # header
        s = strip(line)
        isempty(s) && continue
        parts = split(s, ",")
        nfeat = length(parts) - 1
        for p in parts[1:nfeat]
            push!(values, parse(Float32, p))
        end
        push!(labels, String(parts[end]))
    end
    return reshape(values, nfeat, length(labels)), labels
end

function load_split(rng, path; test_fraction = 0.3)
    X, y = read_file(path)
    test_idx = Int[]
    train_idx = Int[]
    for label in sort(unique(y))
        members = shuffle(rng, [j for j in eachindex(y) if y[j] == label])
        ntest = round(Int, test_fraction * length(members))
        append!(test_idx, members[1:ntest])
        append!(train_idx, members[ntest+1:end])
    end
    return (Xtrain = X[:, train_idx], ytrain = y[train_idx], Xtest = X[:, test_idx], ytest = y[test_idx])
end

end
