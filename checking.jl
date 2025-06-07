using XLSX
using DataFrames
using Dates
using HTTP
using JSON


# Fetch weather data from the external API for a given city and country
function fetch_weather_from_api(city::String, country::String)
    base_url = "https://utony-weather-server.onrender.com/api/weather"
    # Properly encode the city and country for the URL
    city_enc = replace(city, " " => "%20")
    country_enc = replace(country, " " => "%20")
    url = "$base_url?city=$city_enc&country=$country_enc"
    response = HTTP.get(url)
    if response.status == 200
        data = JSON.parse(String(response.body))
        return data
    else
        println("Failed to fetch weather data. Status: ", response.status)
        return nothing
    end
end

# Generate a simple AI weather summary from a dictionary of hourly weather data
function ai_weather_summary_from_dict(weather_dict::Dict, api_key::String, model::String="gemini-2.0-flash")
    # Join all hour info arrays into a single string for the prompt
    weather_string = join([join(v, ", ") for v in values(weather_dict)], "\n")
    url = "https://generativelanguage.googleapis.com/v1/models/$model:generateContent?key=$api_key"
    headers = ["Content-Type" => "application/json", "Accept-Encoding" => "identity"]
    # Compose prompt for the AI model
    user_content = "Give a simple, friendly summary of this day's hourly weather for a user. Make the summary concise and easy to understand for a normal person(3-4 lines max). Always keep the unit in Celsuis except the country is USA or Canada" * weather_string
    data = Dict("contents" => [Dict("parts" => [Dict("text" => user_content)])])
    try
        response = HTTP.post(url, headers, JSON.json(data))
        if response.status != 200
            # Print HTTP error details for debugging
            println("HTTP error occurred while calling Gemini API. Status: $(response.status)")
            println("Response body: ", String(response.body))
            return "HTTP error: Status $(response.status)."
        end
        result = JSON.parse(String(response.body))
        # Extract the AI-generated summary from the response
        if haskey(result, "candidates") && length(result["candidates"]) > 0 &&
           haskey(result["candidates"][1], "content") &&
           haskey(result["candidates"][1]["content"], "parts") &&
           length(result["candidates"][1]["content"]["parts"]) > 0 &&
           haskey(result["candidates"][1]["content"]["parts"][1], "text")
            text = result["candidates"][1]["content"]["parts"][1]["text"]
            # Remove any leading phrase ending with a colon, dash, or period (case-insensitive)
            cleaned = replace(text, r"(?i)^\s*([a-z\s,'’\-]+:|[a-z\s,'’\-]+\.\s*)+" => "")
            return replace(cleaned, "\n" => "")
        else
            return "Error: Unexpected response format from Gemini API.\nRaw response: $(JSON.json(result))"
        end
    catch e
        # Print exception details for debugging
        println("Exception occurred during HTTP/API call: ", e)
        return "HTTP or API error: $(e)"
    end
end


"""
    extract_hourly_weather_strings(weather_data::Dict)

Given weather_data as returned from the API, extract for each hour in each day the following fields:
:tempmax, :tempmin, :precip, :windspeed, :winddir, :solarradiation, :solarenergy, :conditions, :sunrise, :sunset, :visibility, :humidity, :preciptype, :precipprob, :precipcover, :dew, :sealevelpressure, :cloudcover, :snow, :uvindex, :snowdepth

Returns a vector of strings, one per hour, with the values concatenated.

Parameters extracted per hour:
    :tempmax            # Maximum temperature (°F or °C)
    :tempmin            # Minimum temperature (°F or °C)
    :precip             # Precipitation amount
    :windspeed          # Wind speed
    :winddir            # Wind direction
    :solarradiation     # Solar radiation
    :solarenergy        # Solar energy
    :conditions         # Weather conditions (string)
    :sunrise            # Sunrise time (from day)
    :sunset             # Sunset time (from day)
    :visibility         # Visibility
    :humidity         # Humidity (%)
    :preciptype         # Type of precipitation (array)
    :precipprob         # Probability of precipitation
    :precipcover         # Precipitation cover
    :dew                # Dew point
    :sealevelpressure   # Sea level pressure (may be missing, fallback to pressure)
    :cloudcover         # Cloud cover (%)
    :snow               # Snow amount
    :uvindex            # UV index
    :snowdepth          # Snow depth

Expected data structure:
weather_data = Dict(
    "days" => [
        Dict(
            "sunrise" => "...",
            "sunset" => "...",
            "hours" => [
                Dict(
                    "tempmax" => ...,
                    "tempmin" => ...,
                    "precip" => ...,
                    ...
                ),
                ...
            ]
        ),
        ...
    ]
)
"""
function extract_hourly_weather_strings(weather_data::Dict)
    # List of fields to extract from each hour
    fields = [
        :tempmax, :tempmin, :precip, :windspeed, :winddir, :solarradiation, :solarenergy,
        :conditions, :sunrise, :sunset, :visibility, :humidity, :preciptype, :precipprob,
        :precipcover, :dew, :sealevelpressure, :cloudcover, :snow, :uvindex, :snowdepth
    ]
    results = String[]
    # Loop through each day
    for day in get(weather_data, "days", [])
        hours = get(day, "hours", [])
        # For each hour in the day
        for hour in hours
            vals = String[]
            for f in fields
                # Some fields may not exist in the hour dict, use get with default ""
                val = get(hour, String(f), get(day, String(f), ""))
                # If value is an array (e.g., preciptype), join as comma-separated string
                if isa(val, AbstractArray)
                    val_str = join(val, ",")
                else
                    val_str = string(val)
                end
                push!(vals, string(f, "=", val_str))
            end
            push!(results, join(vals, ", "))
        end
    end
    return results
end

# Extract a dictionary of hourly weather data for all days
function extract_hourly_weather_dict(weather_data::Dict)
    fields = [
        :tempmax, :tempmin, :precip, :windspeed, :winddir, :solarradiation, :solarenergy,
        :conditions, :sunrise, :sunset, :visibility, :humidity, :preciptype, :precipprob,
        :precipcover, :dew, :sealevelpressure, :cloudcover, :snow, :uvindex, :snowdepth
    ]
    result_dict = Dict{String, Vector{String}}()
    for day in get(weather_data, "days", [])
        day_date = get(day, "datetime", "")
        sunrise = get(day, "sunrise", "")
        sunset = get(day, "sunset", "")
        hours = get(day, "hours", [])
        for hour in hours
            hour_time = get(hour, "datetime", "")
            # Compose a unique key for the hour (date + time)
            hour_key = string(day_date, " ", hour_time)
            vals = String[]
            for f in fields
                val = get(hour, String(f), get(day, String(f), ""))
                if isa(val, AbstractArray)
                    val_str = join(val, ",")
                else
                    val_str = string(val)
                end
                push!(vals, string(f, "=", val_str))
            end
            result_dict[hour_key] = vals
        end
    end
    return result_dict
end

# Extract a dictionary of hourly weather data for a specific day
function extract_hourly_weather_dict_for_day(weather_data::Dict, day_date::String)
    fields = [
        :tempmax, :tempmin, :precip, :windspeed, :winddir, :solarradiation, :solarenergy,
        :conditions, :sunrise, :sunset, :visibility, :humidity, :preciptype, :precipprob,
        :precipcover, :dew, :sealevelpressure, :cloudcover, :snow, :uvindex, :snowdepth
    ]
    result_dict = Dict{String, Vector{String}}()
    for day in get(weather_data, "days", [])
        if get(day, "datetime", "") == day_date
            hours = get(day, "hours", [])
            for hour in hours
                hour_time = get(hour, "datetime", "")
                hour_key = string(day_date, " ", hour_time)
                vals = String[]
                for f in fields
                    val = get(hour, String(f), get(day, String(f), ""))
                    if isa(val, AbstractArray)
                        val_str = join(val, ",")
                    else
                        val_str = string(val)
                    end
                    push!(vals, string(f, "=", val_str))
                end
                result_dict[hour_key] = vals
            end
            break
        end
    end
    return result_dict
end

# Print hourly weather data for a specific city, country, and date
function getdata(city::String, country::String, day_date::String)
    weather_data = fetch_weather_from_api(city, country)
    if weather_data !== nothing
        hourly_dict_day = extract_hourly_weather_dict_for_day(weather_data, day_date)
        for hour_key in sort(collect(keys(hourly_dict_day)))
            info_array = hourly_dict_day[hour_key]
            println(hour_key, " => ", info_array)
        end
    else
        println("No weather data available.")
    end
end

global country = ""  # Global variable for country (if needed elsewhere)

# Show a weather summary for a specific day using the AI summary function
function show_weather_summary_for_day(city::String, country::String, day_date::String, api_key::String="AIzaSyBzmqE-MTVkKy9_xEhKhhGDj0pfGSi79kQ"; model::String="gemini-2.0-flash")
    try
        weather_data = fetch_weather_from_api(city, country)
        if weather_data !== nothing
            hourly_dict_day = extract_hourly_weather_dict_for_day(weather_data, day_date)
            if !isempty(hourly_dict_day)
                ai_summary = ai_weather_summary_from_dict(hourly_dict_day, api_key, model)
                return ai_summary # Return the summary instead of printing it
            else
                println("No weather data found for the specified date.")
                return nothing
            end
        else
            println("No weather data available.")
            return nothing
        end
    catch e
        println("Error in show_weather_summary_for_day: ", e)
        return "Error in show_weather_summary_for_day: $(e)"
    end
end

# Example usage:
# println(show_weather_summary_for_day("Texas", "USA", "2025-06-07"))