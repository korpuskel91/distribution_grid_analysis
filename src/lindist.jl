using JuMP, JuMPChance
using Ipopt
using Distributions


function Solve_LinDist(buses, lines, generators)

info("Starting LinDist Model")

bus_set = collect(keys(buses))
line_set = collect(keys(lines))
gen_set = collect(keys(generators))
gen_bus = []
for g in keys(generators)
    push!(gen_bus, generators[g].bus_idx)
end
root_bus = 0
for b in keys(buses)
    if buses[b].is_root
        root_bus = b
    end
end

lines_to = Dict()
for l in keys(lines)
    lines_to[lines[l].to_node] = lines[l]
end

v_root = 1

m = Model(solver=IpoptSolver(print_level=3))

@variable(m, v[bus_set] >= 0) #variable for voltage square
@variable(m, fp[bus_set]) #variable for active power flow
@variable(m, fq[bus_set]) # variable for reactive power flow
@variable(m, gp[bus_set]) #variable for active power generation
@variable(m, gq[bus_set]) #variable for reactive power generation

@objective(m, Min, sum((gp[b])*buses[b].generator.cost for b in gen_bus) +
                    sum((gq[b])*buses[b].generator.cost for b in gen_bus))

for b in gen_bus
# All buses with generation
    @constraint(m, gp[b] <= buses[b].generator.g_P_max) #Upper limit constraint for active power generation
    @constraint(m, gp[b] >= 0) #Lower limit constraint for active power generation
    @constraint(m, gq[b] <= buses[b].generator.g_Q_max) #Upper limit constraint for reactive power generation
    @constraint(m, gq[b] >= -buses[b].generator.g_Q_max) #Lower limit constraint for reactive power generation
end

for b in setdiff(bus_set, gen_bus)
# All buses without generation
    @constraint(m, gp[b] == 0)
    @constraint(m, gq[b] == 0)
end

for b in bus_set
# All buses
    @constraint(m, buses[b].d_P - gp[b] + sum(fp[k] for k in buses[b].children) == fp[b])
    @constraint(m, buses[b].d_Q - gq[b] + sum(fq[k] for k in buses[b].children) == fq[b])

    @constraint(m, v[b] <= buses[b].v_max)
    @constraint(m, v[b] >= buses[b].v_min)
end

for b in setdiff(bus_set, [root_bus])
# All buses without root
    b_ancestor = buses[b].ancestor[1]
    @constraint(m, v[b] == v[b_ancestor] - 2*(lines_to[b].r * fp[b] + lines_to[b].x * fq[b]))
    @constraint(m, lines_to[b].s_max^2 >= fp[b]^2 + fq[b]^2)
end

#Voltage and flow constraints for root node
@constraint(m, v[root_bus] == v_root)
@constraint(m, fp[root_bus] == 0)
@constraint(m, fq[root_bus] == 0)

solve(m)


# Prepare Results
bus_results = DataFrame(bus = Any[], d_P = Any[], d_Q = Any[], g_P = Any[], g_Q = Any[], v_squared = Any[])
line_results = DataFrame(line = Any[], from = Any[], to = Any[], f_P = Any[], f_Q = Any[], a_squared = Any[])
for b in bus_set
    res = [b, buses[b].d_P, buses[b].d_Q, getvalue(gp[b]), getvalue(gq[b]), getvalue(v[b])]
    push!(bus_results, res)

    # Calc square current on line
    a_res = 0
    fp_res = getvalue(fp[b])
    fq_res = getvalue(fq[b])
    if b != root_bus
        v_res = getvalue(v[buses[b].ancestor[1]])
        a_res = (fp_res^2 + fq_res^2)/v_res
        lres = [lines_to[b].index, buses[b].ancestor[1], b, fp_res, fq_res, a_res]
        push!(line_results, lres)
    end
end

sort!(bus_results, cols=:bus)
sort!(line_results, cols=:to)

return getobjectivevalue(m), bus_results, line_results
end #Sove_LinDist


function Solve_Multisample_LinDist(buses, lines, generators)

info("Starting LinDist Model")

bus_set = collect(keys(buses))
line_set = collect(keys(lines))
gen_set = collect(keys(generators))
gen_bus = []
for g in keys(generators)
    push!(gen_bus, generators[g].bus_idx)
end
root_bus = 0
for b in keys(buses)
    if buses[b].is_root
        root_bus = b
    end
end

lines_to = Dict()
for l in keys(lines)
    lines_to[lines[l].to_node] = lines[l]
end

v_root = 1

m = Model(solver=IpoptSolver())

@variable(m, v[bus_set] >= 0) #variable for voltage square
@variable(m, fp[bus_set]) #variable for active power flow
@variable(m, fq[bus_set]) # variable for reactive power flow
@variable(m, gp[bus_set]) #variable for active power generation
@variable(m, gq[bus_set]) #variable for reactive power generation

@objective(m, Min, sum((gp[b] + gq[b])*buses[b].generator.cost for b in gen_bus))

for b in gen_bus
# All buses with generation
    @constraint(m, gp[b] <= buses[b].generator.g_P_max) #Upper limit constraint for active power generation
    @constraint(m, gp[b] >= 0) #Lower limit constraint for active power generation
    @constraint(m, gq[b] <= buses[b].generator.g_Q_max) #Upper limit constraint for reactive power generation
    @constraint(m, gq[b] >= -buses[b].generator.g_Q_max) #Lower limit constraint for reactive power generation
end

for b in setdiff(bus_set, gen_bus)
# All buses without generation
    @constraint(m, gp[b] == 0)
    @constraint(m, gq[b] == 0)
end

for b in bus_set
# All buses
    @constraint(m, buses[b].d_P - gp[b] + sum(fp[k] for k in buses[b].children) == fp[b])
    @constraint(m, buses[b].d_Q - gq[b] + sum(fq[k] for k in buses[b].children) == fq[b])

    @constraint(m, v[b] <= buses[b].v_max)
    @constraint(m, v[b] >= buses[b].v_min)
end

for b in setdiff(bus_set, [root_bus])
# All buses without root
    b_ancestor = buses[b].ancestor[1]
    @constraint(m, v[b] == v[b_ancestor] - 2*(lines_to[b].r * fp[b] + lines_to[b].x * fq[b]))
    @constraint(m, lines_to[b].s_max^2 >= fp[b]^2 + fq[b]^2)
end

#Voltage and flow constraints for root node
@constraint(m, v[root_bus] == v_root)
@constraint(m, fp[root_bus] == 0)
@constraint(m, fq[root_bus] == 0)

solve(m)


# Prepare Results
bus_results = DataFrame(bus = Any[], d_P = Any[], d_Q = Any[], g_P = Any[], g_Q = Any[], v_squared = Any[])
line_results = DataFrame(line = Any[], from = Any[], to = Any[], f_P = Any[], f_Q = Any[], a_squared = Any[])
for b in bus_set
    res = [b, buses[b].d_P, buses[b].d_Q, getvalue(gp[b]), getvalue(gq[b]), getvalue(v[b])]
    push!(bus_results, res)

    # Calc square current on line
    a_res = 0
    fp_res = getvalue(fp[b])
    fq_res = getvalue(fq[b])
    if b != root_bus
        v_res = getvalue(v[buses[b].ancestor[1]])
        a_res = (fp_res^2 + fq_res^2)/v_res
        lres = [lines_to[b].index, buses[b].ancestor[1], b, fp_res, fq_res, a_res]
        push!(line_results, lres)
    end
end

sort!(bus_results, cols=:bus)
sort!(line_results, cols=:to)

return getobjectivevalue(m), bus_results, line_results
end #Sove_LinDist
