# my additional functions, to meet the formulation of ACOPF, DCOPF, SOC, SDP, QC of solve_opf_bichler
function build_opf_bichler(pm::AbstractPowerModel, nw::Int=nw_id_default)

    variable_bus_voltage(pm, bounded = false)                #   DCP: defines va / AC: defines re_vi and im_vi and adds constraint V_min^2 <= (vr^2 + vi^2) <= V_max^2
    variable_consumption_generation(pm)     #   All Models: defines x_b, x_bl, y_s, y_sl
    variable_consumption_generation_im(pm)  #   DCP: nothing happens here / AC: add im_(xb/ys) /
    variable_commited(pm)                   #   add u_s variable
    
    
    
    
    objective_max_welfare(pm)               #   objective function of Bichlers formulations - maximize welfare


    
    constraint_bounds_x_bl(pm)              #   add constraint 1 #holds for every model / 0 <= x_bl <= q_bl / constraint.jl

    constraint_inelastic_demand(pm)        #   add constraint 2 # DCOPF, AC, SOC, QC, SDP: sum(x_bl) = x_b 
    
    constraint_bounds_x_b(pm)                  #   add constraint 3 DC, AC, SOC, QC, SDP: min_Pb <= x_b <= max_Pb 
    
    constraint_bounds_Im_xb(pm)             #  for AC, SOC, QC, SDP / -min_Qb <= im_xb <= max_Qb

    constraint_bounds_activegeneration(pm)      #   add constraint 5 # holds for every model / y_sl >= 0  & y_s - u_s*q_sl <= 0

    constraint_generation_balance(pm)       #   add constraint 6 # holds for every model / y_s - sum(y_sl) = 0

    constraint_activegeneration_limits(pm)  #   add constraint 7 & 8 # holds for every model / min_Ps*u_s <= y_s <= max_Ps*u_s

    constraint_reactivegeneration_limits(pm) #  holds for AC, SOC, QC, SDP / y_s - u_s*max_Qs <= 0 & y_s - u_s*min_Qs >= 0 for DC does nothing


    constraint_model_voltage_bichler(pm)      #   add constraint 9 # holds for DC / sum(y_sl) - sum(x_bl) = sum(-B_ik*(va[i] - va[k])) - sum(-B_ki*(va[k] - va[i]))


    for i in ids(pm, nw, :bus)
        # model specific constraints
        constraints_model_sepcific(pm, i)

    end

    #   explanation for model specific constraints
    #   DCOPF: sets constraints for every node i / va[i] \in  [-pi/2, pi/2] && sum(y_is) - sum(x_is) = sum(-B_ik*(va[i] - va[k])) - sum(-B+ki*(va[k] - va[i]))

    #   ACOPF: ...


    # Model ausgeben
    print(pm.model)
    
end


# solver function for the formulations of Prof. Bichler 
function solve_opf_bichler(file, model_type::Type, optimizer; kwargs...)
    return solve_model(file, model_type, optimizer, build_opf_bichler; kwargs...)
end

""
function solve_ac_opf(file, optimizer; kwargs...)
    return solve_opf(file, ACPPowerModel, optimizer; kwargs...)
end

""
function solve_dc_opf(file, optimizer; kwargs...)
    return solve_opf(file, DCPPowerModel, optimizer; kwargs...)
end

""
function solve_opf(file, model_type::Type, optimizer; kwargs...)
    return solve_model(file, model_type, optimizer, build_opf; kwargs...)
end

""
function build_opf(pm::AbstractPowerModel)
    variable_bus_voltage(pm)   # initiates va and vm for every bus in the network
    variable_gen_power(pm)     # initiates pg and qg for every generator in the network pg is the active and qg is the reactive power produces at the end 
    variable_branch_power(pm)   # initiates pf and qf for every branch in the network pf is the active and qf is the reactive power flowing from the from bus to the to bus
    variable_dcline_power(pm)

    objective_min_fuel_and_flow_cost(pm) # defines the cost functions for every generator and builds the objective function

    constraint_model_voltage(pm)    # only does something for SOC, QC and SDP not know yet what

    for i in ids(pm, :ref_buses)
        constraint_theta_ref(pm, i) # constraint 14 / va_refrence_bus = 0.0
    end


    for i in ids(pm, :bus)
        constraint_power_balance(pm, i) # constraints the power balnce regarding production and flows, 
    end                                 #  this is what I need to implement in every of our models, 
                                        #   since we introduce the consumption variables which change this part
    for i in ids(pm, :branch)
        constraint_ohms_yt_from(pm, i)  # implements the Ohms law for the from bus-idx
        constraint_ohms_yt_to(pm, i)   # implements the Ohms law for the to bus-idx

        constraint_voltage_angle_difference(pm, i)  #für acp angmin <= va_fr - va_to <= angmax

        constraint_thermal_limit_from(pm, i)    # implements the thermal limit for the from bus-idx (p_fr^2 + q_fr^2 <= rate_a^2)
        constraint_thermal_limit_to(pm, i)    # implements the thermal limit for the to bus-idx (p_to^2 + q_to^2 <= rate_a^2)
    end

    for i in ids(pm, :dcline)
        constraint_dcline_power_losses(pm, i)
    end
end



"a toy example of how to model with multi-networks"
function solve_mn_opf(file, model_type::Type, optimizer; kwargs...)
    return solve_model(file, model_type, optimizer, build_mn_opf; multinetwork=true, kwargs...)
end

""
function build_mn_opf(pm::AbstractPowerModel)
    for (n, network) in nws(pm)
        variable_bus_voltage(pm, nw=n)
        variable_gen_power(pm, nw=n)
        variable_branch_power(pm, nw=n)
        variable_dcline_power(pm, nw=n)

        constraint_model_voltage(pm, nw=n)

        for i in ids(pm, :ref_buses, nw=n)
            constraint_theta_ref(pm, i, nw=n)
        end

        for i in ids(pm, :bus, nw=n)
            constraint_power_balance(pm, i, nw=n)
        end

        for i in ids(pm, :branch, nw=n)
            constraint_ohms_yt_from(pm, i, nw=n)
            constraint_ohms_yt_to(pm, i, nw=n)

            constraint_voltage_angle_difference(pm, i, nw=n)

            constraint_thermal_limit_from(pm, i, nw=n)
            constraint_thermal_limit_to(pm, i, nw=n)
        end

        for i in ids(pm, :dcline, nw=n)
            constraint_dcline_power_losses(pm, i, nw=n)
        end
    end

    objective_min_fuel_and_flow_cost(pm)
end


"a toy example of how to model with multi-networks and storage"
function solve_mn_opf_strg(file, model_type::Type, optimizer; kwargs...)
    return solve_model(file, model_type, optimizer, build_mn_opf_strg; multinetwork=true, kwargs...)
end

""
function build_mn_opf_strg(pm::AbstractPowerModel)
    for (n, network) in nws(pm)
        variable_bus_voltage(pm, nw=n)
        variable_gen_power(pm, nw=n)
        variable_storage_power_mi(pm, nw=n)
        variable_branch_power(pm, nw=n)
        variable_dcline_power(pm, nw=n)

        constraint_model_voltage(pm, nw=n)

        for i in ids(pm, :ref_buses, nw=n)
            constraint_theta_ref(pm, i, nw=n)
        end

        for i in ids(pm, :bus, nw=n)
            constraint_power_balance(pm, i, nw=n)
        end

        for i in ids(pm, :storage, nw=n)
            constraint_storage_complementarity_mi(pm, i, nw=n)
            constraint_storage_losses(pm, i, nw=n)
            constraint_storage_thermal_limit(pm, i, nw=n)
        end

        for i in ids(pm, :branch, nw=n)
            constraint_ohms_yt_from(pm, i, nw=n)
            constraint_ohms_yt_to(pm, i, nw=n)

            constraint_voltage_angle_difference(pm, i, nw=n)

            constraint_thermal_limit_from(pm, i, nw=n)
            constraint_thermal_limit_to(pm, i, nw=n)
        end

        for i in ids(pm, :dcline, nw=n)
            constraint_dcline_power_losses(pm, i, nw=n)
        end
    end

    network_ids = sort(collect(nw_ids(pm)))

    n_1 = network_ids[1]
    for i in ids(pm, :storage, nw=n_1)
        constraint_storage_state(pm, i, nw=n_1)
    end

    for n_2 in network_ids[2:end]
        for i in ids(pm, :storage, nw=n_2)
            constraint_storage_state(pm, i, n_1, n_2)
        end
        n_1 = n_2
    end

    objective_min_fuel_and_flow_cost(pm)
end




"""
Solves an opf using ptdfs with no explicit voltage or line flow variables.

This formulation is most often used when a small subset of the line flow
constraints are active in the data model.
"""
function solve_opf_ptdf(file, model_type::Type, optimizer; full_inverse=false, kwargs...)
    if !full_inverse
        return solve_model(file, model_type, optimizer, build_opf_ptdf; ref_extensions=[ref_add_connected_components!,ref_add_sm!], kwargs...)
    else
        return solve_model(file, model_type, optimizer, build_opf_ptdf; ref_extensions=[ref_add_connected_components!,ref_add_sm_inv!], kwargs...)
    end
end

""
function build_opf_ptdf(pm::AbstractPowerModel)
    Memento.error(_LOGGER, "build_opf_ptdf is only valid for DCPPowerModels")
end

""
function build_opf_ptdf(pm::DCPPowerModel)
    variable_gen_power(pm)

    for i in ids(pm, :bus)
        expression_bus_power_injection(pm, i)
    end

    objective_min_fuel_cost(pm)

    constraint_model_voltage(pm)

    # this constraint is implicit in this model
    #for i in ids(pm, :ref_buses)
    #    constraint_theta_ref(pm, i)
    #end

    for i in ids(pm, :components)
        constraint_network_power_balance(pm, i)
    end

    for (i, branch) in ref(pm, :branch)
        # requires optional vad parameters
        #constraint_voltage_angle_difference(pm, i)

        # only create these expressions if a line flow is specified
        if haskey(branch, "rate_a")
            expression_branch_power_ohms_yt_from_ptdf(pm, i)
            expression_branch_power_ohms_yt_to_ptdf(pm, i)
        end

        constraint_thermal_limit_from(pm, i)
        constraint_thermal_limit_to(pm, i)
    end
end


""
function ref_add_sm!(ref::Dict{Symbol, <:Any}, data::Dict{String, <:Any})
    apply_pm!(_ref_add_sm!, ref, data)
end


""
function _ref_add_sm!(ref::Dict{Symbol, <:Any}, data::Dict{String, <:Any})
    reference_bus(data) # throws an error if an incorrect number of reference buses are defined
    ref[:sm] = calc_susceptance_matrix(data)
end


""
function ref_add_sm_inv!(ref::Dict{Symbol, <:Any}, data::Dict{String, <:Any})
    apply_pm!(_ref_add_sm_inv!, ref, data)
end


""
function _ref_add_sm_inv!(ref::Dict{Symbol, <:Any}, data::Dict{String, <:Any})
    ref[:sm] = calc_susceptance_matrix_inv(data)
end
