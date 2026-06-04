# Social preview

1280×640 OG images used when the repo URL is shared on Slack, Twitter, iMessage, etc.

- `icon-wordmark-dark.png` — uploaded as the GitHub repo's social preview (Settings → Social preview).
- `icon-wordmark-light.png` — kept for a future Pages site / light-mode contexts.

To update the social preview after replacing the file:

```sh
gh api -X PATCH /repos/danseely/agendum-neo \
  -F social_preview=@design/social-preview/icon-wordmark-dark.png
```

(Or upload via Settings → Social preview in the GitHub UI.)
