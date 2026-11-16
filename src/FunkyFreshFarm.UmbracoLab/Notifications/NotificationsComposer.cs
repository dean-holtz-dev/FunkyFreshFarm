using Umbraco.Cms.Core.Composing;
using Umbraco.Cms.Core.DependencyInjection;
using Umbraco.Cms.Core.Notifications;

namespace FunkyFreshFarm.UmbracoLab.Notifications;

/// <summary>
/// Registers this project's notification handlers. Umbraco discovers composers through
/// <c>AddComposers()</c> in Program.cs, so no change to Program.cs is needed.
/// </summary>
public sealed class NotificationsComposer : IComposer
{
    public void Compose(IUmbracoBuilder builder)
        => builder.AddNotificationHandler<ContentPublishedNotification, ContentPublishedLoggingHandler>();
}
