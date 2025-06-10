using XLSX
using DataFrames
using Dates
using HTTP
using JSON
using DotEnv

if isfile(".env") # Check if the .env file exists in the current directory
    for line in eachline(".env")
        if occursin("=", line)
            key, val = split(line, "=", limit=2)
            ENV[strip(key)] = strip(val)
        end
    end
end

function get_api_key()
    try
        api_key = get(ENV, "API_KEY", nothing)
        if isnothing(api_key) || isempty(api_key)
            throw(ArgumentError("API_KEY environment variable is not set or is empty"))
        end
        return api_key
    catch e
        @error "Failed to get API key" exception=e
        rethrow(e)
    end
end

api_key = get_api_key()

function fetch_weather_from_api(city::String, country::String)
    base_url = "https://utony-weather-server.onrender.com/api/weather"
    city_enc = replace(city, " " => "%20")
    country_enc = replace(country, " " => "%20")
    url = "$base_url?city=$city_enc&country=$country_enc"
    try
        response = HTTP.get(url)
        if response.status == 200
            return JSON.parse(String(response.body))
        else
            println("Failed to fetch weather data. Status: ", response.status)
            return nothing
        end
    catch e
        println("Exception occurred while fetching weather data: ", e)
        return nothing
    end
end

function get_local_location()
    try
        response = HTTP.get("https://ipapi.co/json/")
        if response.status == 200
            location = JSON.parse(String(response.body))
            return get(location, "country_name", "")
        end
        return nothing
    catch e
        return nothing
    end
end

function filter_weather_by_time_of_day(weather_dict::Dict, country::String)
    local_country = get_local_location()
    
    # If location lookup failed or matches user's country, apply time-based filtering
    if local_country === nothing || uppercase(local_country) == uppercase(country)
        current_hour = Dates.hour(now())
        filtered_dict = Dict{String, Vector{String}}()
        
        for (time_key, values) in weather_dict
            hour = parse(Int, split(split(time_key, " ")[2], ":")[1])
            
            if current_hour >= 0 && current_hour < 8
                filtered_dict[time_key] = values
            elseif current_hour >= 12 && current_hour <= 16
                hour >= 12 && (filtered_dict[time_key] = values)
            elseif current_hour >= 19
                hour >= 19 && (filtered_dict[time_key] = values)
            else
                (hour >= current_hour && hour < current_hour + 6) && 
                    (filtered_dict[time_key] = values)
            end
        end
        return filtered_dict
    else
        return weather_dict  # For different countries, return full day data
    end
end

function get_time_context(country::String)
    local_country = get_local_location()
    
    if local_country === nothing || uppercase(local_country) != uppercase(country)
        return "full day's"
    end
    
    current_hour = Dates.hour(now())
    if current_hour >= 0 && current_hour < 8
        return "whole day's"
    elseif current_hour >= 12 && current_hour <= 16
        return "afternoon and evening"
    elseif current_hour >= 19
        return "tonight's"
    else
        return "next few hours'"
    end
end

function ai_weather_summary_from_dict(weather_dict::Dict, api_key::String, country::String, city::String, model::String="gemini-2.0-flash")
    filtered_dict = filter_weather_by_time_of_day(weather_dict, country)
    weather_string = join([join(v, ", ") for v in values(filtered_dict)], "\n")
    time_context = get_time_context(country)
    
    # Determine temperature unit based on country
    temp_unit = uppercase(country) in ["USA", "UNITED STATES", "CANADA"] ? "Fahrenheit" : "Celsius"
    
    url = "https://generativelanguage.googleapis.com/v1/models/$model:generateContent?key=$api_key"
    headers = ["Content-Type" => "application/json", "Accept-Encoding" => "identity"]
    user_content = "Summarize the $time_context weather in no more than 45 words. Use temperatures in $temp_unit. If there's any chance of precipitation, mention it with a short prediction or advice. Avoid any leading phrases or labels. " * weather_string
    data = Dict("contents" => [Dict("parts" => [Dict("text" => user_content)])])
    
    try
        response = HTTP.post(url, headers, JSON.json(data))
        if response.status != 200
            return "HTTP error: Status $(response.status)."
        end
        result = JSON.parse(String(response.body))
        if haskey(result, "candidates") && length(result["candidates"]) > 0 &&
           haskey(result["candidates"][1], "content") &&
           haskey(result["candidates"][1]["content"], "parts") &&
           length(result["candidates"][1]["content"]["parts"]) > 0 &&
           haskey(result["candidates"][1]["content"]["parts"][1], "text")
            text = result["candidates"][1]["content"]["parts"][1]["text"]
            cleaned = replace(text, r"(?i)^\s*([a-z\s,''\-]+:|[a-z\s,''\-]+\.\s*)+" => "")
            cleaned = replace(cleaned, "\n" => "")
            cleaned = strip(cleaned)
            cleaned = uppercasefirst(cleaned)
            if !endswith(cleaned, ".")
                cleaned *= "."
            end
            return cleaned
        else
            return "Error: Unexpected response format from Gemini API."
        end
    catch e
        return "HTTP or API error: $(e)"
    end
end

function extract_hourly_weather_dict_for_day(weather_data::Dict, day_date::String)
    fields = [:tempmax, :tempmin, :precip, :windspeed, :winddir, :solarradiation, :solarenergy,
              :conditions, :sunrise, :sunset, :visibility, :humidity, :preciptype, :precipprob,
              :precipcover, :dew, :sealevelpressure, :cloudcover, :snow, :uvindex, :snowdepth]
    result_dict = Dict{String, Vector{String}}()
    
    for day in get(weather_data, "days", [])
        if get(day, "datetime", "") == day_date
            for hour in get(day, "hours", [])
                hour_time = get(hour, "datetime", "")
                hour_key = string(day_date, " ", hour_time)
                vals = String[]
                for f in fields
                    val = get(hour, String(f), get(day, String(f), ""))
                    val_str = isa(val, AbstractArray) ? join(val, ",") : string(val)
                    push!(vals, string(f, "=", val_str))
                end
                result_dict[hour_key] = vals
            end
            break
        end
    end
    return result_dict
end

function show_weather_summary_for_day(city::String="Texas", country::String="USA", day_date::String="2024-07-03"; model::String="gemini-2.0-flash")
    try
        weather_data = fetch_weather_from_api(city, country)
        if weather_data !== nothing
            hourly_dict_day = extract_hourly_weather_dict_for_day(weather_data, day_date)
            if !isempty(hourly_dict_day)
                return ai_weather_summary_from_dict(hourly_dict_day, api_key, country, city, model)
            end
            println("No weather data found for the specified date.")
            return nothing
        end
        println("No weather data available.")
        return nothing
    catch e
        return "Error in show_weather_summary_for_day: $(e)"
    end
end