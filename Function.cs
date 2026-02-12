using Amazon.Lambda.Core;
using Amazon.Lambda.APIGatewayEvents;
using System.Text.Json;

[assembly: LambdaSerializer(typeof(Amazon.Lambda.Serialization.SystemTextJson.DefaultLambdaJsonSerializer))]

namespace HelloLambda;

public class Function
{
    public APIGatewayProxyResponse FunctionHandler(APIGatewayProxyRequest request, ILambdaContext context)
    {
        context.Logger.LogInformation($"Request received at {DateTime.UtcNow:O}");
        context.Logger.LogInformation($"HTTP Method: {request.HttpMethod}");
        context.Logger.LogInformation($"Path: {request.Path}");

        var body = new
        {
            message = "Hello World from AWS Lambda (.NET 8)!",
            timestamp = DateTime.UtcNow,
            requestId = context.AwsRequestId,
            functionName = context.FunctionName
        };

        return new APIGatewayProxyResponse
        {
            StatusCode = 200,
            Headers = new Dictionary<string, string>
            {
                { "Content-Type", "application/json" },
                { "X-Request-Id", context.AwsRequestId }
            },
            Body = JsonSerializer.Serialize(body)
        };
    }
}
