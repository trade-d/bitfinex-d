module trading.bitfinex;

import vibe.d;

///
alias TickerResult = float[10];

///
@path("/v2/")
interface BitfinexPublicAPIv2
{
    ///
    @method(HTTPMethod.GET)
    @path("ticker/:symbol")
    TickerResult ticker(string _symbol);
}

///
@path("/v1/")
interface BitfinexPublicAPI
{
    ///
    @method(HTTPMethod.GET)
    @path("symbols")
    string[] symbols();
}

///
struct OrderHistoryItem
{
    Json exchange;
    bool is_cancelled;
    string avg_execution_price;
    string timestamp;
    string price;
    bool is_live;
    bool is_hidden;
    string type;
    string executed_amount;
    string src;
    long cid;
    string cid_date;
    long id;
    string symbol;
    bool was_forced;
    string original_amount;
    string side;
    Json gid;
    Json oco_order;
    string remaining_amount;
}

///
alias OrderHistoryResult = OrderHistoryItem[];

///
struct BFXOrderStatus
{
    string exchange;
    string avg_execution_price;
    bool is_live;
    bool is_cancelled;
    bool is_hidden;
    bool was_forced;
    long id;
    long cid;
    string remaining_amount;
    string executed_amount;
    string timestamp;
    string price;
    string type;
    string src;
    string cid_date; //"2018-01-16"
    string symbol; //"xrpusd"
    string original_amount;
    string side;
    Json gid;
    Json oco_order;
}

///
interface BitfinexPrivateAPI
{
    ///
    Json accountInfos();
    ///
    OrderHistoryResult orderHistory();
    ///
    BFXOrderStatus newOrder(string symbol, string amount, string price,
            string side, string ordertype);
    ///
    BFXOrderStatus orderStatus(long id);
}

///
final class Bitfinex : BitfinexPublicAPI, BitfinexPublicAPIv2, BitfinexPrivateAPI
{
    private static immutable API_URL = "https://api.bitfinex.com";

    private string key;
    private string secret;

    private BitfinexPublicAPI publicApi;
    private BitfinexPublicAPIv2 publicApiV2;

    ///
    this(string key, string secret)
    {
        this.key = key;
        this.secret = secret;
        publicApiV2 = new RestInterfaceClient!BitfinexPublicAPIv2(API_URL);
        publicApi = new RestInterfaceClient!BitfinexPublicAPI(API_URL);
    }

    ///
    TickerResult ticker(string symbol)
    {
        return publicApiV2.ticker(symbol);
    }

    ///
    string[] symbols()
    {
        return publicApi.symbols();
    }

    unittest
    {
        auto api = new Bitfinex("", "");
        auto res = api.symbols();
        assert(res.length > 0);
    }

    ///
    Json accountInfos()
    {
        static immutable METHOD_URL = "/v1/account_infos";

        return request!Json(METHOD_URL, Json.emptyObject);
    }

    ///
    OrderHistoryResult orderHistory()
    {
        static immutable METHOD_URL = "/v1/orders/hist";

        return request!OrderHistoryResult(METHOD_URL, Json.emptyObject);
    }

    ///
    BFXOrderStatus newOrder(string symbol, string amount, string price,
            string side, string ordertype)
    {

        static immutable METHOD_URL = "/v1/order/new";

        Json params = Json.emptyObject;
        params["symbol"] = symbol;
        params["amount"] = amount;
        params["price"] = price;
        params["exchange"] = "bitfinex";
        params["side"] = side;
        params["type"] = ordertype;

        return request!BFXOrderStatus(METHOD_URL, params);
    }

    ///
    BFXOrderStatus orderStatus(long id)
    {
        static immutable METHOD_URL = "/v1/order/status";

        Json params = Json.emptyObject;
        params["order_id"] = id;

        return request!BFXOrderStatus(METHOD_URL, params);
    }

    private auto request(T)(string path, Json postData = Json.emptyObject)
    {
        import std.digest.sha : SHA384, toHexString, LetterCase;
        import std.conv : to;
        import std.base64 : Base64;
        import std.digest.hmac : hmac;
        import std.string : representation;

        postData["request"] = path;
        postData["nonce"] = Clock.currStdTime().to!string;

        auto res = requestHTTP(API_URL ~ path, (scope HTTPClientRequest req) {

            string bodyData = postData.toString;
            string payload = Base64.encode(cast(ubyte[]) bodyData);

            //logInfo("payload: %s", payload);

            string signature = payload.representation.hmac!SHA384(secret.representation)
                .toHexString!(LetterCase.lower).idup;

            req.method = HTTPMethod.POST;
            req.headers["X-BFX-APIKEY"] = key;
            req.headers["X-BFX-PAYLOAD"] = payload;
            req.headers["X-BFX-SIGNATURE"] = signature;
            req.headers["Content-Type"] = "application/json";
            req.headers["Content-Length"] = (bodyData.length).to!string;

            req.bodyWriter.write(bodyData);
        });
        scope (exit)
        {
            res.dropBody();
        }

        if (res.statusCode == 200)
        {
            auto json = res.readJson();

            //logInfo("Response: %s", json);

            return deserializeJson!T(json);
        }
        else
        {
            logDebug("API Error: %s", res.bodyReader.readAllUTF8());
            logError("API Error Code: %s", res.statusCode);
            throw new Exception("API Error");
        }
    }
}
