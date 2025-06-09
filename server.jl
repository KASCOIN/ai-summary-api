using DotEnv
DotEnv.config()
using HTTP, JSON, Dates

# Assuming checking.jl contains the show_weather_summary_for_day function
include("checking.jl")

function handle_request(req::HTTP.Request)
    # Define common CORS headers
    # For development, "*" allows all origins. In production, replace with your frontend's domain (e.g., "http://yourfrontend.com")
    cors_headers = [
        "Access-Control-Allow-Origin" => "*",
        "Access-Control-Allow-Methods" => "GET, POST, OPTIONS", # Allow common methods
        "Access-Control-Allow-Headers" => "Content-Type, Authorization", # Allow common headers
    ]

    # Handle preflight OPTIONS requests for CORS (browser sends this before actual request)
    if req.method == "OPTIONS"
        println("Handling OPTIONS preflight request from: ", HTTP.getheader(req, "Origin"))
        return HTTP.Response(200, cors_headers)
    end

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
                # Include CORS headers even for error responses
                return HTTP.Response(400, cors_headers, "Missing city or country parameters")
            end

            formatted_date = Dates.format(Dates.today(), "YYYY-mm-dd") # Provide a default value
            try
                date = Dates.Date(date_str, "YYYY-mm-dd") # Validate date format
                println("Date parsing successful: ", date)
                formatted_date = Dates.format(date, "YYYY-mm-dd")
            catch e
                println("Error parsing date: ", e)
                # Include CORS headers for error responses
                return HTTP.Response(400, cors_headers, "Invalid date format. UseYYYY-mm-dd.")
            end

            try
                println("Calling show_weather_summary_for_day with: ", city, ", ", country, ", ", formatted_date)
                
                # Assume show_weather_summary_for_day returns a string or a Dict.
                # We'll ensure it's always converted to a JSON object for consistency.
                weather_summary_raw = show_weather_summary_for_day(city, country, formatted_date) # Pass API_KEY

                if weather_summary_raw !== nothing
                    println("Weather summary data generated.")

                    response_body = weather_summary_raw  # Use raw summary directly

                    # Combine existing CORS headers with Content-Type
                    final_headers = ["Content-Type" => "text/plain"; cors_headers] # Change Content-Type to text/plain
                    println("Returning 200 OK with JSON summary.")
                    return HTTP.Response(200, final_headers, response_body)
                else
                    println("Weather data not found for summary.")
                    return HTTP.Response(404, cors_headers, "Weather data not found")
                end
            catch e
                println("Error in weather processing: ", e)
                return HTTP.Response(500, cors_headers, "Internal server error during weather summary generation")
            end
        else
            println("Not Found - Method: ", req.method, ", Target: ", req.target)
            return HTTP.Response(404, cors_headers, "Not found")
        end
    catch e
        println("Error handling request: ", e)
        return HTTP.Response(500, cors_headers, "Internal server error")
    end
end

# Get port from environment variable or default to 8000
port = parse(Int, get(ENV, "PORT", "8000"))

println("Server starting on port $port")
HTTP.serve(handle_request, "0.0.0.0", port)
