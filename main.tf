// <copyright file="TitulosHandler.cs" company="Banco Fibra">
// Direitos autorais (c) Banco Fibra. Todos os direitos reservados.
// </copyright>

using Amazon.Lambda.Core;

// Assembly attribute to enable the Lambda function's JSON input to be converted into a .NET class.
[assembly: LambdaSerializer(typeof(Amazon.Lambda.Serialization.SystemTextJson.DefaultLambdaJsonSerializer))]

namespace Fibra.Produtos.CessaoCredito.FCT.Handlers;

/// <summary>
/// Handler mínimo de exemplo: retorna uma mensagem fixa.
/// </summary>
public class TitulosHandler
{
    /// <summary>
    /// Retorna a mensagem "Hello World" (ignora o payload de entrada).
    /// </summary>
    /// <param name="input">Payload opcional (não utilizado).</param>
    /// <param name="context">Contexto da execução Lambda.</param>
    /// <returns>Mensagem de saudação.</returns>
    public Task<string> HelloWorldAsync(object? input, ILambdaContext context)
    {
        _ = input;
        _ = context;
        return Task.FromResult("Hello World");
    }
}
 
