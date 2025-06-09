# Julia Weather App

A sophisticated weather application built with Julia that provides intelligent weather summaries based on location and time of day.

## Features

- Real-time weather data fetching
- Location-aware weather summaries
- Time-sensitive weather reporting
- AI-powered weather descriptions using Google's Gemini API
- Automatic temperature unit conversion (Celsius/Fahrenheit)
- Smart context-based filtering for local vs. remote locations

## Prerequisites

- Julia 1.6 or higher
- Google Gemini API key
- Internet connection for API access

## Installation

1. Clone the repository:
```bash
git clone <https://my-julia-server-api.onrender.com/weather?city=Madrid&country=Spain&date=2025-06-09.git>
cd weather-app
```

2. Create a `.env` file in the project root:
```
API_KEY=your_gemini_api_key_here
```

3. Install dependencies:
```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()
```

## Usage

```julia
# Basic usage
show_weather_summary_for_day("London", "UK", "2024-03-20")

# With default values (Texas, USA, current date)
show_weather_summary_for_day()

# Specify different date
show_weather_summary_for_day("Paris", "France", "2024-03-21")
```

## Features Explanation

- Local Weather: When checking weather for your current country, summaries are time-sensitive:
  - 00:00-08:00: Full day forecast
  - 12:00-16:00: Afternoon through evening
  - 19:00-23:59: Night forecast
  - Other times: Next 6 hours

- Remote Weather: When checking other countries, provides comprehensive day summaries

## Environment Variables

- `API_KEY`: Your Google Gemini API key

## Dependencies

- HTTP.jl
- JSON.jl
- Dates.jl
- DotEnv.jl
- XLSX.jl
- DataFrames.jl

## Docker Support

Build and run with Docker:

```bash
docker build -t weather-app .
docker run -p 8000:8000 -e API_KEY=your_api_key weather-app
```

## License

MIT License

## Author

[Nwosu Kasiemobechukwu Faith]
