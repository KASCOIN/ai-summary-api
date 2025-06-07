using HTTP, JSON, Dates

include("checking.jl")

function handle_request(req::HTTP.Request)
    try
        println("Request Method: ", req.method)
        println("Request Target: ", req.target)
        println("Request Params: ", HTTP.queryparams(req))

        if req.method == "GET" && startswith(req.target, "/weather")
            params = HTTP.queryparams(req)
            city = get(params, "city", "")
            country = get(params, "country", "")
            date_str = get(params, "date", Dates.format(Dates.today(), "YYYY-mm-dd"))

            println("City: ", city)
            println("Country: ", country)
            println("Date String: ", date_str)

            if isempty(city) || isempty(country)
                return HTTP.Response(400, "Missing city or country parameters")
            end

            formatted_date = Dates.format(Dates.today(), "YYYY-mm-dd") # Provide a default value
            try
                date = Dates.Date(date_str, "YYYY-mm-dd") # Validate date format
                println("Date parsing successful: ", date)
                formatted_date = Dates.format(date, "YYYY-mm-dd")
            catch e
                println("Error parsing date: ", e)
                return HTTP.Response(400, "Invalid date format. Use YYYY-mm-dd.")
            end

            try
                println("Calling show_weather_summary_for_day with: ", city, ", ", country, ", ", formatted_date)
                weather_summary = show_weather_summary_for_day(city, country, formatted_date)

                if weather_summary !== nothing
                    println("Weather summary: ", weather_summary)
                    return HTTP.Response(200, "OK") # Simplify response for now
                else
                    return HTTP.Response(404, "Weather data not found")
                end
            catch e
                println("Error in weather processing: ", e)
                return HTTP.Response(500, "Internal server error")
            end
        else
            println("Not Found - Method: ", req.method, ", Target: ", req.target)
            return HTTP.Response(404, "Not found")
        end
    catch e
        println("Error handling request: ", e)
        return HTTP.Response(500, "Internal server error")
    end
end

HTTP.serve(handle_request, "0.0.0.0", 8000)
println("Server started on port 8000") # The server is already running