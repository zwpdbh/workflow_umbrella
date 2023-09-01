defmodule Http.RestClient do
  alias Http.RestClient

  defstruct [
    :url,
    :header,
    :query_str
  ]

  def new() do
    %RestClient{}
  end

  def add_header(key, value) do
    %{key => value}
  end

  def add_header(headers, key, value) when is_map_key(headers, key) do
    %{headers | key => value}
  end

  def add_header(headers, key, value) do
    Map.put_new(headers, key, value)
  end

  def map_to_tuple_list(%{} = some_map) do
    Enum.map(some_map, fn {key, value} -> {key, value} end)
  end

  def add_body(key, value) do
    %{key => value}
  end

  def add_body(body, key, value) when is_map_key(body, key) do
    %{body | key => value}
  end

  def add_body(body, key, value) do
    Map.put_new(body, key, value)
  end

  def encode_map_to_json(%{} = body) when body == %{} do
    ""
  end

  def encode_map_to_json(%{} = body) do
    Jason.encode!(body)
  end

  def add_query(key, value) do
    %{key => value}
  end

  def add_query(params, key, value) when is_map_key(params, key) do
    %{params | key => value}
  end

  def add_query(params, key, value) do
    Map.put_new(params, key, value)
  end

  def encode_query_map_to_uri(%{} = params) do
    params
    |> URI.encode_query()
  end

  def get_request(uri, nil, %{} = header_map) do
    HTTPoison.get(uri, map_to_tuple_list(header_map))
  end

  def get_request(uri, %{} = query_map, %{} = header_map) do
    query_str = query_map |> encode_query_map_to_uri()
    HTTPoison.get(uri <> "?" <> query_str, map_to_tuple_list(header_map))
  end

  # For example: uri is: "https://api.twelvedata.com/time_series"
  # and query_map is:
  # %{
  #   "apikey" => "<api_key>",
  #   "format" => "json",
  #   "interval" => "30min",
  #   "outputsize" => "20",
  #   "symbol" => "AAPL"
  # }
  def get_request(uri, %{} = query_map) do
    query_str = query_map |> encode_query_map_to_uri()
    HTTPoison.get(uri <> "?" <> query_str)
  end

  def get_request(uri) do
    HTTPoison.get(uri)
  end

  def post_request(uri, %{} = body_map, %{} = header_map, %{} = query_map) do
    query_str = query_map |> encode_query_map_to_uri()

    HTTPoison.post(
      uri <> "?" <> query_str,
      encode_map_to_json(body_map),
      map_to_tuple_list(header_map)
    )
  end

  # Special case for Azure: we need to pass the body information as "form-data".
  # Therefore, we need to handle it differently when we encounter heander type:
  # "Content-type" => "application/x-www-form-urlencoded"
  def post_request(
        uri,
        %{} = body_map,
        %{"Content-type" => "application/x-www-form-urlencoded"} = header_map
      ) do
    HTTPoison.post(
      uri,
      # Special case for Azure authorization: https://stackoverflow.com/questions/49513122/oauth2-error-aadsts90014-the-request-body-must-contain-the-following-parameter
      URI.encode_query(body_map),
      map_to_tuple_list(header_map)
    )
  end

  def post_request(uri, %{} = body_map, %{} = header_map) do
    HTTPoison.post(uri, encode_map_to_json(body_map), map_to_tuple_list(header_map))
  end

  def post_request(uri, %{} = body_map) do
    HTTPoison.post(uri, encode_map_to_json(body_map))
  end

  def put_request(uri, nil, nil, %{} = header_map) do
    HTTPoison.put(
      uri,
      "",
      map_to_tuple_list(header_map)
    )
  end

  def put_request(uri, %{} = body_map, %{} = query_map, %{} = header_map) do
    query_str = query_map |> encode_query_map_to_uri()

    HTTPoison.put(
      uri <> "?" <> query_str,
      encode_map_to_json(body_map),
      map_to_tuple_list(header_map)
    )
  end

  def put_request(uri, nil, %{} = query_map, %{} = header_map) do
    query_str = query_map |> encode_query_map_to_uri()

    HTTPoison.put(
      uri <> "?" <> query_str,
      "",
      map_to_tuple_list(header_map)
    )
  end

  def put_request(uri, body, %{} = query_map, %{} = header_map) when is_binary(body) do
    query_str = query_map |> encode_query_map_to_uri()

    HTTPoison.put(
      uri <> "?" <> query_str,
      body,
      map_to_tuple_list(header_map)
    )
  end

  def delete_request(url, headers) do
    HTTPoison.delete(url, headers)
  end
end
