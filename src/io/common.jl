#add my parsing function to receive data from .raw and .json format
function parse_file(raw::String, json::String; import_all=false, validate=true)
    
    #parse the raw data
    raw_data = parse_file(raw; import_all=import_all, validate=validate)

    #parse the json data
    json_data = parse_file(json; import_all=import_all, validate=false)
    #merge the two data structures
    
    return merge_data(raw_data, json_data)


end

#helper function to merge the data fro json and raw file
function merge_data(raw_data::Dict{String, Any}, json_data::Dict{String, Any})

    #create a new dictionary to store the merged data
    merged_data = Dict{String, Any}()

    #merge the loads' data in json file with the loads' data in raw file
    for i in keys(raw_data["load"])
        for j in keys(json_data["loads"])
            if raw_data["load"][i]["source_id"][2] == json_data["loads"][j]["bus"] && raw_data["load"][i]["source_id"][3] == json_data["loads"][j]["id"]
                merged_data = merge(raw_data["load"][i], json_data["loads"][j])
                cblocks_dict = make_dict(json_data["loads"][j]["cblocks"])
                merged_data["cblocks"] = cblocks_dict
                raw_data["load"][i] = merged_data
            end
        end
    end

    #merge the generators' data in json file with the generators' data in raw file
    for i in keys(raw_data["gen"])
        for j in keys(json_data["generators"])
            if raw_data["gen"][i]["source_id"][2] == json_data["generators"][j]["bus"] && raw_data["gen"][i]["source_id"][3] == json_data["generators"][j]["id"]
                merged_data = merge(raw_data["gen"][i], json_data["generators"][j])
                cblocks_dict = make_dict(json_data["generators"][j]["cblocks"])
                merged_data["cblocks"] = cblocks_dict
                raw_data["gen"][i] = merged_data
            end
        end
    end


    return raw_data
end

#helper function to make the array of dictionaries to a dictionary structure - its makes it easier later on to access the data
function make_dict(data::Array{Any, 1})
    # initiate new dictionary
    dict_from_array = Dict{Int, Dict{String, Any}}()

    # add every dictionary from the array to the new dictionary with its index as the key   
    for (index, dict) in enumerate(data)
        dict_from_array[index] = dict
    end
    return dict_from_array
end


"""
    parse_file(file; import_all)

Parses a Matpower .m `file` or PTI (PSS(R)E-v33) .raw `file` into a
PowerModels data structure. All fields from PTI files will be imported if
`import_all` is true (Default: false).
"""
function parse_file(file::String; import_all=false, validate=true)
    pm_data = open(file) do io
        pm_data = parse_file(io; import_all=import_all, validate=validate, filetype=split(lowercase(file), '.')[end])
    end
    return pm_data
end


"Parses the iostream from a file"
function parse_file(io::IO; import_all=false, validate=true, filetype="json")
    if filetype == "m"
        pm_data = PowerModels.parse_matpower(io, validate=validate)
    elseif filetype == "raw"
        pm_data = PowerModels.parse_psse(io; import_all=import_all, validate=validate)
    elseif filetype == "json"
        pm_data = PowerModels.parse_json(io; validate=validate)
    else
        Memento.error(_LOGGER, "Unrecognized filetype: \".$filetype\", Supported extensions are \".raw\", \".m\" and \".json\"")
    end

    return pm_data
end


"""
Make a PM multinetwork data structure of the given filenames
"""
function parse_files(filenames::String...)
    mn_data = Dict{String, Any}(
        "nw" => Dict{String, Any}(),
        "per_unit" => true,
        "multinetwork" => true,
    )

    names = Array{String, 1}()

    for (i, filename) in enumerate(filenames)
        data = PowerModels.parse_file(filename)

        delete!(data, "multinetwork")
        delete!(data, "per_unit")

        mn_data["nw"]["$i"] = data
        push!(names, "$(data["name"])")
    end

    mn_data["name"] = join(names, " + ")

    return mn_data
end


"""
    export_file(file, data)

Export a PowerModels data structure to the file according of the extension:
    - `.m` : Matpower
    - `.raw` : PTI (PSS(R)E-v33)
    - `.json` : JSON 
"""
function export_file(file::AbstractString, data::Dict{String, Any})
    if occursin(".", file) 
        open(file, "w") do io
            export_file(io, data, filetype=split(lowercase(file), '.')[end])
        end
    else
        Memento.error(_LOGGER, "The file must have an extension")
    end
end


function export_file(io::IO, data::Dict{String, Any}; filetype="json")
    if filetype == "m"
        PowerModels.export_matpower(io, data)
    elseif filetype == "raw"
        PowerModels.export_pti(io, data)
    elseif filetype == "json"
        stringdata = JSON.json(data)
        write(io, stringdata)
    else
        Memento.error(_LOGGER, "Unrecognized filetype: \".$filetype\", Supported extensions are \".raw\", \".m\" and \".json\"")
    end
end


"""
Runs various data quality checks on a PowerModels data dictionary.
Applies modifications in some cases.  Reports modified component ids.
"""
function correct_network_data!(data::Dict{String,<:Any})
    check_connectivity(data)
    check_status(data)
    check_reference_bus(data)
    make_per_unit!(data)

    correct_transformer_parameters!(data)
    correct_voltage_angle_differences!(data)
    correct_thermal_limits!(data)
    correct_current_limits!(data)
    correct_branch_directions!(data)

    check_branch_loops(data)
    correct_dcline_limits!(data)

    data_ep = _IM.ismultiinfrastructure(data) ? data["it"][pm_it_name] : data

    if length(data_ep["gen"]) > 0 && any(gen["gen_status"] != 0 for (i, gen) in data_ep["gen"])
        correct_bus_types!(data)
    end

    check_voltage_setpoints(data)
    check_storage_parameters(data)
    check_switch_parameters(data)

    correct_cost_functions!(data)

    simplify_cost_terms!(data)
end
