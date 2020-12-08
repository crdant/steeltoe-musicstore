using Azure.Identity;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using OrderService.Models;
using Steeltoe.Discovery.Client;
using Steeltoe.Extensions.Configuration.Kubernetes;
using Steeltoe.Management.Endpoint;
using System;

namespace OrderService
{
    public class Program
    {
        public static void Main(string[] args)
        {
            var host = CreateHostBuilder(args).Build();

            SeedDatabase(host);

            host.Run();
        }

        public static IHostBuilder CreateHostBuilder(string[] args) =>
            Host.CreateDefaultBuilder(args)
                .ConfigureWebHostDefaults(webbuilder => webbuilder.UseStartup<Startup>())
                .ConfigureAppConfiguration(AddRemoteConfiguration)
                .AddAllActuators()
                .AddDiscoveryClient();

        private static void SeedDatabase(IHost host)
        {
            using var scope = host.Services.CreateScope();
            var services = scope.ServiceProvider;
            SampleData.InitializeOrderDatabase(services);
        }

        private static Action<HostBuilderContext, IConfigurationBuilder> AddRemoteConfiguration =>
            (builderContext, configBuilder) =>
            {
                configBuilder.AddKubernetes();
                configBuilder.AddEnvironmentVariables();
            };

        private static ILoggerFactory GetLoggerFactory()
        {
            IServiceCollection serviceCollection = new ServiceCollection();
            serviceCollection.AddLogging(builder => builder.SetMinimumLevel(LogLevel.Trace).AddConsole());
            return serviceCollection.BuildServiceProvider().GetService<ILoggerFactory>();
        }
    }
}
