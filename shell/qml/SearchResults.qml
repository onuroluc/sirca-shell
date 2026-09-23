// The search panel's results: KRunner's engine through Milou. Behind a Loader (by URL) in Search.qml: org.kde.milou is a
// Plasma-internal module, so when it is missing or has changed the panel still opens and only says "Nothing found".
import org.kde.milou as Milou

Milou.ResultsModel { limit: 14 }
