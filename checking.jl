using XLSX
using DataFrames
using Dates
using HTTP
using JSON
using DotEnv

for line in eachline(".env")
    if occursin("=", line)
        key, val = split(line, "=", limit=2)
        ENV[strip(key)] = strip(val)
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

function ai_weather_summary_from_dict(weather_dict::Dict, api_key::String, model::String="gemini-2.0-flash")
    weather_string = join([join(v, ", ") for v in values(weather_dict)], "\n")
    
    url = "https://generativelanguage.googleapis.com/v1/models/$model:generateContent?key=$api_key"
    headers = ["Content-Type" => "application/json", "Accept-Encoding" => "identity"]
    user_content = "Provide only the weather summary and advice in plain text without any headers, labels, or introductory phrases. Make it concise (3-4 lines) and easy to understand. Always keep the unit in Celsius except for USA or Canada. Include practical advice for the day. " * weather_string
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
                return ai_weather_summary_from_dict(hourly_dict_day, api_key, model)
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