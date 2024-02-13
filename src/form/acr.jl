### rectangular form of the non-convex AC equations

# model specific constraints 
# constraints for AC model after the formulation of Bichler et al. 2023
function constraints_model_sepcific(pm::AbstractACRModel, bus_id::Int, nw::Int=nw_id_default)

    constraint_real_xb_ys(pm, bus_id)
    constraint_im_xb_ys(pm, bus_id)

end

function constraint_real_xb_ys(pm::AbstractACRModel, bus_id::Int, nw::Int=nw_id_default)

    #access variables
    Re_y_s = var(pm, nw, :y_s)
    Re_x_b = var(pm, nw, :x_b)

    vi = var(pm, nw, :vi)   #imaginary part
    vr = var(pm, nw, :vr)   #real part

    sum_y_is = 0.0
    sum_x_ib = 0.0
    try
        sum_y_is = sum(Re_y_s[s] for s in ref(pm, nw, :bus_gens, bus_id))
    catch
        sum_y_is = 0
    end

    try
        sum_x_ib = sum(Re_x_b[b] for b in ref(pm, nw, :bus_loads, bus_id))
    catch
        sum_x_ib = 0
    end

    #access parameters
    sum_node = 0.0

    for branch in ref(pm, nw, :arcs)
        (id, f_bus, t_bus) = branch

        if f_bus == bus_id
            branch_data = ref(pm, nw, :branch, id)
            g, b = calc_branch_y(branch_data)
            #b = 0.01
            #g = 0.01

            sum_node = sum_node + (vr[f_bus] * (g*vr[t_bus] - b*vi[t_bus]) + vi[f_bus] * (b*vr[t_bus] + g*vi[t_bus]))
        end
    end

    JuMP.@constraint(pm.model, sum_y_is - sum_x_ib - sum_node == 0)

end

function constraint_im_xb_ys(pm::AbstractACRModel, bus_id::Int, nw::Int=nw_id_default)

        #access variables
        Im_y_s = var(pm, nw, :Im_ys)
        Im_x_b = var(pm, nw, :Im_xb)
    
        vi = var(pm, nw, :vi)   #imaginary part
        vr = var(pm, nw, :vr)   #real part
    
        sum_Im_y_is = 0.0
        sum_Im_x_ib = 0.0
        try
            sum_y_is = sum(Im_y_s[s] for s in ref(pm, nw, :bus_gens, bus_id))  #  :bus_gens holds every generator at the specific bus with id == bus_id
        catch
            sum_y_is = 0
        end
    
        try
            sum_x_ib = sum(Im_x_b[b] for b in ref(pm, nw, :bus_loads, bus_id)) #   :bus_loads holds every load at the specific load with id == bus_id
        catch
            sum_x_ib = 0
        end
    
        #access parameters
        sum_node = 0.0
    
        for branch in ref(pm, nw, :arcs)
            (id, f_bus, t_bus) = branch
    
            if f_bus == bus_id
                branch_data = ref(pm, nw, :branch, id)
                g, b = calc_branch_y(branch_data)
                b = 0.01
                g = 0.01
    
                sum_node = sum_node + (vr[f_bus] * (-b*vr[t_bus] - g*vi[t_bus]) + vi[f_bus] * (g*vr[t_bus] - b*vi[t_bus]))
            end
        end
    
        JuMP.@constraint(pm.model, sum_Im_y_is - sum_Im_x_ib - sum_node == 0)

end

""
function variable_bus_voltage(pm::AbstractACRModel; nw::Int=nw_id_default, bounded::Bool=true, kwargs...)
    variable_bus_voltage_real(pm; nw=nw, bounded=bounded, kwargs...)
    variable_bus_voltage_imaginary(pm; nw=nw, bounded=bounded, kwargs...)

    if bounded
        for (i,bus) in ref(pm, nw, :bus)
            constraint_voltage_magnitude_bounds(pm, i, nw=nw)
        end

        # does not seem to improve convergence
        #wr_min, wr_max, wi_min, wi_max = ref_calc_voltage_product_bounds(pm.ref[:buspairs])
        #for bp in ids(pm, nw, :buspairs)
        #    i,j = bp
        #    JuMP.@constraint(pm.model, wr_min[bp] <= vr[i]*vr[j] + vi[i]*vi[j])
        #    JuMP.@constraint(pm.model, wr_max[bp] >= vr[i]*vr[j] + vi[i]*vi[j])
        #
        #    JuMP.@constraint(pm.model, wi_min[bp] <= vi[i]*vr[j] - vr[i]*vi[j])
        #    JuMP.@constraint(pm.model, wi_max[bp] >= vi[i]*vr[j] - vr[i]*vi[j])
        #end
    end
end


"`vmin <= vm[i] <= vmax`"
function constraint_voltage_magnitude_bounds(pm::AbstractACRModel, n::Int, i, vmin, vmax)
    @assert vmin <= vmax
    vr = var(pm, n, :vr, i)
    vi = var(pm, n, :vi, i)

    JuMP.@constraint(pm.model, vmin^2 <= (vr^2 + vi^2) <= vmax^2)
end

"`v[i] == vm`"
function constraint_voltage_magnitude_setpoint(pm::AbstractACRModel, n::Int, i, vm)
    vr = var(pm, n, :vr, i)
    vi = var(pm, n, :vi, i)

    JuMP.@constraint(pm.model, (vr^2 + vi^2) == vm^2)
end


"reference bus angle constraint"
function constraint_theta_ref(pm::AbstractACRModel, n::Int, i::Int)
    JuMP.@constraint(pm.model, var(pm, n, :vi)[i] == 0)
end


function constraint_power_balance(pm::AbstractACRModel, n::Int, i::Int, bus_arcs, bus_arcs_dc, bus_arcs_sw, bus_gens, bus_storage, bus_pd, bus_qd, bus_gs, bus_bs)
    vr = var(pm, n, :vr, i)
    vi = var(pm, n, :vi, i)
    p    = get(var(pm, n),    :p, Dict()); _check_var_keys(p, bus_arcs, "active power", "branch")
    q    = get(var(pm, n),    :q, Dict()); _check_var_keys(q, bus_arcs, "reactive power", "branch")
    pg   = get(var(pm, n),   :pg, Dict()); _check_var_keys(pg, bus_gens, "active power", "generator")
    qg   = get(var(pm, n),   :qg, Dict()); _check_var_keys(qg, bus_gens, "reactive power", "generator")
    ps   = get(var(pm, n),   :ps, Dict()); _check_var_keys(ps, bus_storage, "active power", "storage")
    qs   = get(var(pm, n),   :qs, Dict()); _check_var_keys(qs, bus_storage, "reactive power", "storage")
    psw  = get(var(pm, n),  :psw, Dict()); _check_var_keys(psw, bus_arcs_sw, "active power", "switch")
    qsw  = get(var(pm, n),  :qsw, Dict()); _check_var_keys(qsw, bus_arcs_sw, "reactive power", "switch")
    p_dc = get(var(pm, n), :p_dc, Dict()); _check_var_keys(p_dc, bus_arcs_dc, "active power", "dcline")
    q_dc = get(var(pm, n), :q_dc, Dict()); _check_var_keys(q_dc, bus_arcs_dc, "reactive power", "dcline")


    cstr_p = JuMP.@constraint(pm.model,
        sum(p[a] for a in bus_arcs)
        + sum(p_dc[a_dc] for a_dc in bus_arcs_dc)
        + sum(psw[a_sw] for a_sw in bus_arcs_sw)
        ==
        sum(pg[g] for g in bus_gens)
        - sum(ps[s] for s in bus_storage)
        - sum(pd for pd in values(bus_pd))
        - sum(gs for gs in values(bus_gs))*(vr^2 + vi^2)
    )
    cstr_q = JuMP.@constraint(pm.model,
        sum(q[a] for a in bus_arcs)
        + sum(q_dc[a_dc] for a_dc in bus_arcs_dc)
        + sum(qsw[a_sw] for a_sw in bus_arcs_sw)
        ==
        sum(qg[g] for g in bus_gens)
        - sum(qs[s] for s in bus_storage)
        - sum(qd for qd in values(bus_qd))
        + sum(bs for bs in values(bus_bs))*(vr^2 + vi^2)
    )

    if _IM.report_duals(pm)
        sol(pm, n, :bus, i)[:lam_kcl_r] = cstr_p
        sol(pm, n, :bus, i)[:lam_kcl_i] = cstr_q
    end
end

""
function constraint_power_balance_ls(pm::AbstractACRModel, n::Int, i::Int, bus_arcs, bus_arcs_dc, bus_arcs_sw, bus_gens, bus_storage, bus_pd, bus_qd, bus_gs, bus_bs)
    vr = var(pm, n, :vr, i)
    vi = var(pm, n, :vi, i)
    p    = get(var(pm, n),    :p, Dict()); _check_var_keys(p, bus_arcs, "active power", "branch")
    q    = get(var(pm, n),    :q, Dict()); _check_var_keys(q, bus_arcs, "reactive power", "branch")
    pg   = get(var(pm, n),   :pg, Dict()); _check_var_keys(pg, bus_gens, "active power", "generator")
    qg   = get(var(pm, n),   :qg, Dict()); _check_var_keys(qg, bus_gens, "reactive power", "generator")
    ps   = get(var(pm, n),   :ps, Dict()); _check_var_keys(ps, bus_storage, "active power", "storage")
    qs   = get(var(pm, n),   :qs, Dict()); _check_var_keys(qs, bus_storage, "reactive power", "storage")
    psw  = get(var(pm, n),  :psw, Dict()); _check_var_keys(psw, bus_arcs_sw, "active power", "switch")
    qsw  = get(var(pm, n),  :qsw, Dict()); _check_var_keys(qsw, bus_arcs_sw, "reactive power", "switch")
    p_dc = get(var(pm, n), :p_dc, Dict()); _check_var_keys(p_dc, bus_arcs_dc, "active power", "dcline")
    q_dc = get(var(pm, n), :q_dc, Dict()); _check_var_keys(q_dc, bus_arcs_dc, "reactive power", "dcline")

    z_demand = get(var(pm, n), :z_demand, Dict()); _check_var_keys(z_demand, keys(bus_pd), "power factor", "load")
    z_shunt = get(var(pm, n), :z_shunt, Dict()); _check_var_keys(z_shunt, keys(bus_gs), "power factor", "shunt")

    cstr_p = JuMP.@constraint(pm.model,
        sum(p[a] for a in bus_arcs)
        + sum(p_dc[a_dc] for a_dc in bus_arcs_dc)
        + sum(psw[a_sw] for a_sw in bus_arcs_sw)
        ==
        sum(pg[g] for g in bus_gens)
        - sum(ps[s] for s in bus_storage)
        - sum(pd*z_demand[i] for (i,pd) in bus_pd)
        - sum(gs*z_shunt[i] for (i,gs) in bus_gs)*(vr^2 + vi^2)
    )
    cstr_q =  JuMP.@constraint(pm.model,
        sum(q[a] for a in bus_arcs)
        + sum(q_dc[a_dc] for a_dc in bus_arcs_dc)
        + sum(qsw[a_sw] for a_sw in bus_arcs_sw)
        ==
        sum(qg[g] for g in bus_gens)
        - sum(qs[s] for s in bus_storage)
        - sum(qd*z_demand[i] for (i,qd) in bus_qd)
        + sum(bs*z_shunt[i] for (i,bs) in bus_bs)*(vr^2 + vi^2)
    )

    if _IM.report_duals(pm)
        sol(pm, n, :bus, i)[:lam_kcl_r] = cstr_p
        sol(pm, n, :bus, i)[:lam_kcl_i] = cstr_q
    end
end



""
function expression_branch_power_ohms_yt_from(pm::AbstractACRModel, n::Int, f_bus, t_bus, f_idx, t_idx, g, b, g_fr, b_fr, tr, ti, tm)
    vr_fr = var(pm, n, :vr, f_bus)
    vr_to = var(pm, n, :vr, t_bus)
    vi_fr = var(pm, n, :vi, f_bus)
    vi_to = var(pm, n, :vi, t_bus)

    var(pm, n, :p)[f_idx] =  (g+g_fr)/tm^2*(vr_fr^2 + vi_fr^2) + (-g*tr+b*ti)/tm^2*(vr_fr*vr_to + vi_fr*vi_to) + (-b*tr-g*ti)/tm^2*(vi_fr*vr_to - vr_fr*vi_to)
    var(pm, n, :q)[f_idx] = -(b+b_fr)/tm^2*(vr_fr^2 + vi_fr^2) - (-b*tr-g*ti)/tm^2*(vr_fr*vr_to + vi_fr*vi_to) + (-g*tr+b*ti)/tm^2*(vi_fr*vr_to - vr_fr*vi_to)
end


""
function expression_branch_power_ohms_yt_to(pm::AbstractACRModel, n::Int, f_bus, t_bus, f_idx, t_idx, g, b, g_to, b_to, tr, ti, tm)
    vr_fr = var(pm, n, :vr, f_bus)
    vr_to = var(pm, n, :vr, t_bus)
    vi_fr = var(pm, n, :vi, f_bus)
    vi_to = var(pm, n, :vi, t_bus)

    var(pm, n, :p)[t_idx] =  (g+g_to)*(vr_to^2 + vi_to^2) + (-g*tr-b*ti)/tm^2*(vr_fr*vr_to + vi_fr*vi_to) + (-b*tr+g*ti)/tm^2*(-(vi_fr*vr_to - vr_fr*vi_to))
    var(pm, n, :q)[t_idx] = -(b+b_to)*(vr_to^2 + vi_to^2) - (-b*tr+g*ti)/tm^2*(vr_fr*vr_to + vi_fr*vi_to) + (-g*tr-b*ti)/tm^2*(-(vi_fr*vr_to - vr_fr*vi_to))
end


"""
Creates Ohms constraints (yt post fix indicates that Y and T values are in rectangular form)
"""
function constraint_ohms_yt_from(pm::AbstractACRModel, n::Int, f_bus, t_bus, f_idx, t_idx, g, b, g_fr, b_fr, tr, ti, tm)
    p_fr = var(pm, n, :p, f_idx)
    q_fr = var(pm, n, :q, f_idx)
    vr_fr = var(pm, n, :vr, f_bus)
    vr_to = var(pm, n, :vr, t_bus)
    vi_fr = var(pm, n, :vi, f_bus)
    vi_to = var(pm, n, :vi, t_bus)

    JuMP.@constraint(pm.model, p_fr ==  (g+g_fr)/tm^2*(vr_fr^2 + vi_fr^2) + (-g*tr+b*ti)/tm^2*(vr_fr*vr_to + vi_fr*vi_to) + (-b*tr-g*ti)/tm^2*(vi_fr*vr_to - vr_fr*vi_to) )
    JuMP.@constraint(pm.model, q_fr == -(b+b_fr)/tm^2*(vr_fr^2 + vi_fr^2) - (-b*tr-g*ti)/tm^2*(vr_fr*vr_to + vi_fr*vi_to) + (-g*tr+b*ti)/tm^2*(vi_fr*vr_to - vr_fr*vi_to) )
end

"""
Creates Ohms constraints (yt post fix indicates that Y and T values are in rectangular form)
"""
function constraint_ohms_yt_to(pm::AbstractACRModel, n::Int, f_bus, t_bus, f_idx, t_idx, g, b, g_to, b_to, tr, ti, tm)
    p_to = var(pm, n, :p, t_idx)
    q_to = var(pm, n, :q, t_idx)
    vr_fr = var(pm, n, :vr, f_bus)
    vr_to = var(pm, n, :vr, t_bus)
    vi_fr = var(pm, n, :vi, f_bus)
    vi_to = var(pm, n, :vi, t_bus)

    JuMP.@constraint(pm.model, p_to ==  (g+g_to)*(vr_to^2 + vi_to^2) + (-g*tr-b*ti)/tm^2*(vr_fr*vr_to + vi_fr*vi_to) + (-b*tr+g*ti)/tm^2*(-(vi_fr*vr_to - vr_fr*vi_to)) )
    JuMP.@constraint(pm.model, q_to == -(b+b_to)*(vr_to^2 + vi_to^2) - (-b*tr+g*ti)/tm^2*(vr_fr*vr_to + vi_fr*vi_to) + (-g*tr-b*ti)/tm^2*(-(vi_fr*vr_to - vr_fr*vi_to)) )
end


""
function constraint_storage_losses(pm::AbstractACRModel, n::Int, i, bus, r, x, p_loss, q_loss)
    vr = var(pm, n, :vr, bus)
    vi = var(pm, n, :vi, bus)
    ps = var(pm, n, :ps, i)
    qs = var(pm, n, :qs, i)
    sc = var(pm, n, :sc, i)
    sd = var(pm, n, :sd, i)
    qsc = var(pm, n, :qsc, i)

    JuMP.@constraint(pm.model, ps + (sd - sc) == p_loss + r*(ps^2 + qs^2)/(vr^2 + vi^2))
    JuMP.@constraint(pm.model, qs == qsc + q_loss + x*(ps^2 + qs^2)/(vr^2 + vi^2))
end


function constraint_current_limit_from(pm::AbstractACRModel, n::Int, f_idx, c_rating_a)
    l,i,j = f_idx

    vr_fr = var(pm, n, :vr, i)
    vi_fr = var(pm, n, :vi, i)

    p_fr = var(pm, n, :p, f_idx)
    q_fr = var(pm, n, :q, f_idx)
    JuMP.@constraint(pm.model, p_fr^2 + q_fr^2 <= (vr_fr^2 + vi_fr^2)*c_rating_a^2)
end

function constraint_current_limit_to(pm::AbstractACRModel, n::Int, t_idx, c_rating_a)
    l,j,i = t_idx

    vr_to = var(pm, n, :vr, j)
    vi_to = var(pm, n, :vi, j)

    p_to = var(pm, n, :p, t_idx)
    q_to = var(pm, n, :q, t_idx)
    JuMP.@constraint(pm.model, p_to^2 + q_to^2 <= (vr_to^2 + vi_to^2)*c_rating_a^2)
end


"""
branch voltage angle difference bounds
"""
function constraint_voltage_angle_difference(pm::AbstractACRModel, n::Int, f_idx, angmin, angmax)
    i, f_bus, t_bus = f_idx

    vr_fr = var(pm, n, :vr, f_bus)
    vr_to = var(pm, n, :vr, t_bus)
    vi_fr = var(pm, n, :vi, f_bus)
    vi_to = var(pm, n, :vi, t_bus)

    JuMP.@constraint(pm.model, (vi_fr*vr_to - vr_fr*vi_to) <= tan(angmax)*(vr_fr*vr_to + vi_fr*vi_to))
    JuMP.@constraint(pm.model, (vi_fr*vr_to - vr_fr*vi_to) >= tan(angmin)*(vr_fr*vr_to + vi_fr*vi_to))
end

""
function sol_data_model!(pm::AbstractACRModel, solution::Dict)
    apply_pm!(_sol_data_model_acr!, solution)
end


""
function _sol_data_model_acr!(solution::Dict)
    if haskey(solution, "bus")
        for (i, bus) in solution["bus"]
            if haskey(bus, "vr") && haskey(bus, "vi")
                bus["vm"] = sqrt(bus["vr"]^2 + bus["vi"]^2)
                bus["va"] = atan(bus["vi"], bus["vr"])

                delete!(bus, "vr")
                delete!(bus, "vi")
            end
        end
    end
end
