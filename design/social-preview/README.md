# Social preview

1280×640 OG images used when the repo URL is shared on Slack, Twitter, iMessage, etc.

## In context

How the dark variant unfurls when the repo URL is pasted into Slack:

![Slack unfurl of the agendum-neo repo URL showing the GitHub link preview with the dark social-preview image](slack-unfurl.png)

## Variants

### Dark

Uploaded as the GitHub repo's social preview.

![Agendum Neo social preview, dark variant — app icon and wordmark on a dark background](icon-wordmark-dark.png)

### Light

Kept for a future Pages site / light-mode contexts.

![Agendum Neo social preview, light variant — app icon and wordmark on a light background](icon-wordmark-light.png)

## Updating the social preview

GitHub doesn't expose the social preview upload via the REST or GraphQL APIs — it's UI-only. To replace it:

1. Open https://github.com/danseely/agendum-neo/settings.
2. Scroll to **Social preview**.
3. Click **Edit** → **Upload an image…** and pick `design/social-preview/icon-wordmark-dark.png`.
