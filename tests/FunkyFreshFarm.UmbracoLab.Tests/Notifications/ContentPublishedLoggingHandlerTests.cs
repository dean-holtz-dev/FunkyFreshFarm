using FunkyFreshFarm.UmbracoLab.Notifications;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Testing;
using NSubstitute;
using Umbraco.Cms.Core.Events;
using Umbraco.Cms.Core.Models;
using Umbraco.Cms.Core.Notifications;

namespace FunkyFreshFarm.UmbracoLab.Tests.Notifications;

public class ContentPublishedLoggingHandlerTests
{
    [Fact]
    public void Logs_one_information_entry_per_published_document()
    {
        var logger = new FakeLogger<ContentPublishedLoggingHandler>();
        var handler = new ContentPublishedLoggingHandler(logger);
        var basilKey = Guid.Parse("6d1f2c3a-4b5e-4f60-8a71-92b3c4d5e6f7");
        IContent[] published =
        [
            CreateContent("plantPage", "Basil", 1072, basilKey),
            CreateContent("homePage", "Home", 1069, Guid.NewGuid()),
        ];

        handler.Handle(new ContentPublishedNotification(published, new EventMessages()));

        IReadOnlyList<FakeLogRecord> records = logger.Collector.GetSnapshot();
        Assert.Equal(2, records.Count);
        Assert.All(records, record => Assert.Equal(LogLevel.Information, record.Level));

        FakeLogRecord basil = records[0];
        Assert.Equal($"Published plantPage Basil (id 1072, key {basilKey})", basil.Message);
        Assert.Equal("plantPage", basil.GetStructuredStateValue("ContentTypeAlias"));
        Assert.Equal("Basil", basil.GetStructuredStateValue("ContentName"));
        Assert.Equal("1072", basil.GetStructuredStateValue("ContentId"));
        Assert.Equal(basilKey.ToString(), basil.GetStructuredStateValue("ContentKey"));
    }

    [Fact]
    public void Logs_nothing_when_no_documents_were_published()
    {
        var logger = new FakeLogger<ContentPublishedLoggingHandler>();
        var handler = new ContentPublishedLoggingHandler(logger);

        handler.Handle(new ContentPublishedNotification(Array.Empty<IContent>(), new EventMessages()));

        Assert.Empty(logger.Collector.GetSnapshot());
    }

    private static IContent CreateContent(string contentTypeAlias, string name, int id, Guid key)
    {
        var contentType = Substitute.For<ISimpleContentType>();
        contentType.Alias.Returns(contentTypeAlias);

        var content = Substitute.For<IContent>();
        content.ContentType.Returns(contentType);
        content.Name.Returns(name);
        content.Id.Returns(id);
        content.Key.Returns(key);
        return content;
    }
}
