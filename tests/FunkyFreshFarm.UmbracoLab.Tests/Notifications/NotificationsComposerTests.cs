using FunkyFreshFarm.UmbracoLab.Notifications;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using Umbraco.Cms.Core.DependencyInjection;
using Umbraco.Cms.Core.Events;
using Umbraco.Cms.Core.Notifications;

namespace FunkyFreshFarm.UmbracoLab.Tests.Notifications;

public class NotificationsComposerTests
{
    [Fact]
    public void Registers_the_logging_handler_as_a_transient_ContentPublished_handler()
    {
        var services = new ServiceCollection();
        var builder = Substitute.For<IUmbracoBuilder>();
        builder.Services.Returns(services);

        new NotificationsComposer().Compose(builder);

        ServiceDescriptor descriptor = Assert.Single(
            services,
            d => d.ServiceType == typeof(INotificationHandler<ContentPublishedNotification>));
        Assert.Equal(typeof(ContentPublishedLoggingHandler), descriptor.ImplementationType);
        Assert.Equal(ServiceLifetime.Transient, descriptor.Lifetime);
    }
}
