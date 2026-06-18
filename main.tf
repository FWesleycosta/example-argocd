// <copyright file="TitulosHandler.cs" company="Banco Fibra">
// Direitos autorais (c) Banco Fibra. Todos os direitos reservados.
// </copyright>
using Amazon.Lambda.Core;
using Datadog.Trace;

// Assembly attribute to enable the Lambda function's JSON input to be converted into a .NET class.
[assembly: LambdaSerializer(typeof(Amazon.Lambda.Serialization.SystemTextJson.DefaultLambdaJsonSerializer))]

namespace Fibra.Produtos.CessaoCredito.FCT.Handlers;

/// <summary>
/// Handler mínimo de exemplo: gera um trace de APM para validação no Datadog.
/// </summary>
public class TitulosHandler
{
    private static readonly HttpClient Http = new();

    /// <summary>
    /// Cria um span manual (e um span filho de HTTP) só para validar o APM no Datadog.
    /// </summary>
    /// <param name="input">Payload opcional (não utilizado).</param>
    /// <param name="context">Contexto da execução Lambda.</param>
    /// <returns>Mensagem de saudação.</returns>
    public async Task<string> HelloWorldAsync(object? input, ILambdaContext context)
    {
        _ = input;

        // Span manual: garante que um trace exista, mesmo que a auto-instrumentação
        // não capture o entrypoint do handler.
        using var scope = Tracer.Instance.StartActive("titulos.hello_world");
        scope.Span.ResourceName = "HelloWorldAsync";
        scope.Span.SetTag("test.apm", "validation");
        scope.Span.SetTag("aws.request_id", context.AwsRequestId);

        // Chamada HTTP simples: a auto-instrumentação do HttpClient deve criar um span filho.
        try
        {
            using var resp = await Http.GetAsync("https://checkip.amazonaws.com");
            scope.Span.SetTag("demo.http_status", ((int)resp.StatusCode).ToString());
        }
        catch (Exception ex)
        {
            scope.Span.SetTag("error", "true");
            scope.Span.SetTag("error.msg", ex.Message);
        }

        return "Hello World";
    }
}
