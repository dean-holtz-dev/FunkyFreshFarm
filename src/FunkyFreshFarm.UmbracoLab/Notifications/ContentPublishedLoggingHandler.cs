using Umbraco.Cms.Core.Events;
using Umbraco.Cms.Core.Models;
using Umbraco.Cms.Core.Notifications;

namespace FunkyFreshFarm.UmbracoLab.Notifications;

/// <summary>
/// Writes one log entry per document published.
/// </summary>
/// <remarks>
/// <see cref="ContentPublishedNotification"/> is raised after the publish transaction has committed, on the
/// thread that performed the publish. The entry contains identifiers and the content type only, never
/// property values, so it is safe to keep in shared logs.
/// </remarks>
public sealed class ContentPublishedLoggingHandler(ILogger<ContentPublishedLoggingHandler> logger)
    : INotificationHandler<ContentPublishedNotification>
{
    public void Handle(ContentPublishedNotification notification)
    {
        foreach (IContent content in notification.PublishedEntities)
        {
            logger.LogInformation(
                "Published {ContentTypeAlias} {ContentName} (id {ContentId}, key {ContentKey})",
                content.ContentType.Alias,
                content.Name,
                content.Id,
                content.Key);
        }
    }
}
