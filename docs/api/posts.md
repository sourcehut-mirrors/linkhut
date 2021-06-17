# Posts

## `/v1/posts/update`

Returns the most recent time a bookmark was added, updated or deleted.

Use this before calling posts/all to see if the data has changed since the last fetch.

### Examples

#### XML

```xml
<?xml version="1.0" encoding="UTF-8"?>
<update code="done" inboxnew="" time="2020-12-22T17:19:59Z"/>
```

#### JSON

```json
{"update_time":"2020-12-29T21:16:29Z"}
```

## `/v1/posts/add`

Add a new bookmark.

### Arguments

- `&url={URL}` (required) — The url of the item.
- `&description={...}` (required) — The description of the item.
- `&extended={...}` (optional) — Notes for the item.
- `&tags={...}` (optional) — Tags for the item (comma delimited).
- `&dt={CCYY-MM-DDThh:mm:ssZ}` (optional) — Datestamp of the item (format “CCYY-MM-DDThh:mm:ssZ”). Requires a LITERAL “T” and “Z” like in ISO8601 at http://www.cl.cam.ac.uk/~mgk25/iso-time.html for Example: `1984-09-01T14:21:31Z`.
- `&replace=no` (optional) — Don’t replace post if given url has already been posted.
- `&shared=no` (optional) — Make the item private.

### Examples

#### XML

If the post was successful:

```xml
<result code="done" />
```

If the post failed:

```xml
<result code="something went wrong" />
```

#### JSON

If the post was successful:

```json
{"result_code":"done"}
```

If the post failed:

```json
{"result_code":"something went wrong"}
```

## `/v1/posts/delete`

Delete a bookmark.

### Arguments

- `&url={URL}` (required) — The URL of the item.

### Examples

#### XML

```xml
<result code="done" />
```

#### JSON

```json
{"result_code":"done"}
```

## `/v1/posts/get`

Returns one or more posts on a single day matching the arguments. If no date or url is given, date of most recent bookmark will be used.

### Arguments

- `&tag={TAG}+{TAG}+...+{TAG}` (optional) — Filter by this tag.
- `&dt={CCYY-MM-DDThh:mm:ssZ}` (optional) — Filter by this date, defaults to the most recent date on which bookmarks were saved.
- `&url={URL}` (optional) — Fetch a bookmark for this URL, regardless of date.  Note: Be sure to URL-encode the argument value.
- `&hashes={MD5}+{MD5}+...+{MD5}` (optional) — Fetch multiple bookmarks by one or more URL MD5s regardless of date, separated by URL-encoded spaces (i.e. `‘+’`).
- `&meta=yes` (optional) — Include change detection signatures on each item in a ‘meta’ attribute. Clients wishing to maintain a synchronized local store of bookmarks should retain the value of this attribute — its value will change when any significant field of the bookmark changes.

### Examples

#### XML

```shell
$ curl -H Authorization:'Bearer <TOKEN>' 'https://api.ln.ht/v1/posts/get?tag=webdev&meta=yes'
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<posts dt="2020-12-23" tag="" user="user">
    <post description="MDN web docs" 
          extended="Resources for developers, by developers." 
          hash="c2a340b85102725118e3449741d7b551" 
          href="https://developer.mozilla.org/" 
          others="1" 
          tag="webdev dom javascript" 
          time="2020-12-23T19:29:57Z"/>
</posts>
```

```shell
$ curl -H Authorization:'Bearer <TOKEN>' 'https://api.ln.ht/v1/posts/get?url=https%3A%2F%2Fsourcehut.org%2F'
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<posts dt="2020-12-23" tag="" user="user">
    <post description="sourcehut - the hacker's forge" 
          extended="sourcehut is a network of useful open source tools for software project maintainers and collaborators, including git repos, bug tracking, continuous integration, and mailing lists."
          hash="f76bae21f8ea04facdb544655745c924"
          href="https://sourcehut.org/" 
          others="0" 
          tag="git oss software-forge"
          time="2020-12-23T19:51:48Z"/>
</posts>
```

#### JSON

```shell
$ curl -H Accept:'application/json' -H Authorization:'Bearer <TOKEN>' 'https://api.ln.ht/v1/posts/get?tag=webdev&meta=yes'
```

```json
{
  "posts": [
    {
      "description": "sourcehut - the hacker's forge",
      "extended": "sourcehut is a network of useful open source tools for software project maintainers and collaborators, including git repos, bug tracking, continuous integration, and mailing lists.",
      "hash": "f76bae21f8ea04facdb544655745c924",
      "href": "https://sourcehut.org/",
      "meta": "8f4f71216f404ce3442bae67564d88cd",
      "shared": "yes",
      "tags": "git oss open-source software collaboration development",
      "time": "2020-12-24T16:11:14Z",
      "toread": "no"
    }
  ]
}
```

```shell
$ curl -H Accept:'application/json' -H Authorization:'Bearer <TOKEN>' 'https://api.ln.ht/v1/posts/get?url=https%3A%2F%2Fsourcehut.org%2F'
```

```json
{
  "posts": [
    {
      "description": "sourcehut - the hacker's forge",
      "extended": "sourcehut is a network of useful open source tools for software project maintainers and collaborators, including git repos, bug tracking, continuous integration, and mailing lists.",
      "hash": "f76bae21f8ea04facdb544655745c924",
      "href": "https://sourcehut.org/",
      "meta": null,
      "shared": "yes",
      "tags": "git oss open-source software collaboration development",
      "time": "2020-12-24T16:11:14Z",
      "toread": "no"
    }
  ]
}
```

## `/v1/posts/recent`

Returns a list of the user's most recent posts, filtered by tag.

### Arguments

- `&tag={TAG}` (optional) — Filter by this tag.
- `&count={1..100}` (optional) — Number of items to retrieve (Default:15, Maximum:100).

### Examples

#### XML

```shell
$ curl -H Authorization:'Bearer <TOKEN>' 'https://api.ln.ht/v1/posts/recent'
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<posts dt="2020-12-23" tag="" user="user">
    <post description="sourcehut - the hacker's forge" 
          extended="sourcehut is a network of useful open source tools for software project maintainers and collaborators, including git repos, bug tracking, continuous integration, and mailing lists." hash="f76bae21f8ea04facdb544655745c924"
          href="https://sourcehut.org/" others="0" tag="git oss software-forge" time="2020-12-23T19:51:48Z"/>
    <post description="MDN web docs" 
          extended="Resources for developers, by developers." hash="c2a340b85102725118e3449741d7b551" 
          href="https://developer.mozilla.org/" others="1" tag="webdev dom javascript" time="2020-12-23T19:29:57Z"/>
  ...
</posts>
```

#### JSON

```shell
$ curl -H Accept:'application/json' -H Authorization:'Bearer <TOKEN>' 'https://api.ln.ht/v1/posts/recent'
```

```json
{
  "posts": [
    {
      "description": "sourcehut - the hacker's forge",
      "extended": "sourcehut is a network of useful open source tools for software project maintainers and collaborators, including git repos, bug tracking, continuous integration, and mailing lists.",
      "hash": "f76bae21f8ea04facdb544655745c924",
      "href": "https://sourcehut.org/",
      "meta": "8f4f71216f404ce3442bae67564d88cd",
      "shared": "yes",
      "tags": "git oss open-source software collaboration development",
      "time": "2020-12-24T16:11:14Z",
      "toread": "no"
    },
    {
      "description": "MDN web docs",
      "extended": "Resources for developers, by developers.",
      "hash": "c2a340b85102725118e3449741d7b551",
      "href": "https://developer.mozilla.org/",
      "meta": "3cbac080ba42fca7fd9ef58674f70f95",
      "shared": "yes",
      "tags": "webdev dom javascript",
      "time": "2020-12-23T19:29:20Z",
      "toread": "no"
    },
    ...
  ]
}
```

## `/v1/posts/dates`

Returns a list of dates with the number of posts at each date.

### Arguments

- `&tag={TAG}` (optional) — Filter by this tag.

### Examples

#### XML

```xml
<dates tag="" user="user">
    <date count="2" date="2020-12-23"/>
    <date count="1" date="2020-12-22"/>
    <date count="1" date="2020-12-15"/>
    <date count="3" date="2020-12-11"/>
    <date count="3" date="2020-11-27"/>
    <date count="1" date="2020-11-16"/>
    <date count="1" date="2020-10-08"/>
    <date count="4" date="2020-05-27"/>
</dates>
```

#### JSON

```json
{
  "dates": {
    "2020-12-23": 2,
    "2020-12-22": 1,
    "2020-12-15": 1,
    "2020-12-11": 3,
    "2020-11-27": 3,
    "2020-11-16": 1,
    "2020-10-08": 1,
    "2020-05-27": 4
  }
}
```

## `/v1/posts/all`

Returns all bookmarks in the user's account. Please use sparingly. Call the update function to see if you need to fetch this at all.

### Arguments

- `&tag={TAG}` (optional) — Filter by this tag.
- `&start={xx}` (optional) — Start returning posts this many results into the set.
- `&results={xx}` (optional) — Return up to this many results. By default, up to 1000 bookmarks are returned, and a maximum of 100000 bookmarks is supported via this API.
- `&fromdt={CCYY-MM-DDThh:mm:ssZ}` (optional) — Filter for posts on this date or later.
- `&todt={CCYY-MM-DDThh:mm:ssZ}` (optional) — Filter for posts on this date or earlier.
- `&meta=yes` (optional) — Include change detection signatures on each item in a ‘meta’ attribute. Clients wishing to maintain a synchronized local store of bookmarks should retain the value of this attribute - its value will change when any significant field of the bookmark changes.

### Examples

#### XML

```shell
$ curl -H Authorization:'Bearer <TOKEN>' 'https://api.ln.ht/v1/posts/all'
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
    <posts tag="" user="user">
    <post description="sourcehut - the hacker's forge" extended="sourcehut is a network of useful open source tools for software project maintainers and collaborators, including git repos, bug tracking, continuous integration, and mailing lists." 
          hash="f76bae21f8ea04facdb544655745c924" href="https://sourcehut.org/" others="0" tag="git oss software-forge" time="2020-12-23T19:51:48Z"/>
    <post description="MDN web docs" extended="Resources for developers, by developers." 
          hash="c2a340b85102725118e3449741d7b551" href="https://developer.mozilla.org/" others="1" tag="webdev dom javascript" time="2020-12-23T19:29:57Z"/>
    ...
</posts>
```

#### JSON

```shell
$ curl -H Accept:'application/json' -H Authorization:'Bearer <TOKEN>' 'https://api.ln.ht/v1/posts/all'
```

```json
[
  {
    "description": "sourcehut - the hacker's forge",
    "extended": "sourcehut is a network of useful open source tools for software project maintainers and collaborators, including git repos, bug tracking, continuous integration, and mailing lists.",
    "hash": "f76bae21f8ea04facdb544655745c924",
    "href": "https://sourcehut.org/",
    "meta": null,
    "shared": "yes",
    "tags": "git oss open-source software collaboration development",
    "time": "2020-12-24T16:11:14Z",
    "toread": "no"
  },
  {
    "description": "MDN web docs",
    "extended": "Resources for developers, by developers.",
    "hash": "c2a340b85102725118e3449741d7b551",
    "href": "https://developer.mozilla.org/",
    "meta": null,
    "shared": "yes",
    "tags": "webdev dom javascript",
    "time": "2020-12-23T19:29:20Z",
    "toread": "no"
  },
  ...
]
```

## `/v1/posts/all?hashes`

Returns a change manifest of all posts. Call the update function to see if you need to fetch this at all.

This method is intended to provide information on changed bookmarks, without the overhead of a complete download of all post data.

Each post element returned offers a `url` attribute containing an URL MD5, with an associated `meta` attribute containing the current change detection signature for that bookmark.

### Examples

#### XML

```shell
$ curl -H Authorization:'Bearer <TOKEN>' 'https://api.ln.ht/v1/posts/all?hashes'
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<posts>
  <post meta="6967ef478d23a7e42eb8d490a38cda4f" url="f76bae21f8ea04facdb544655745c924"/>
  <post meta="c5a81e89d4e60b2bfba66a7c4dc6a636" url="c2a340b85102725118e3449741d7b551"/>
  ...
</posts>
```

#### JSON

```shell
$ curl -H Accept:'application/json' -H Authorization:'Bearer <TOKEN>' 'https://api.ln.ht/v1/posts/all?hashes'
```

```json
[
  {
    "meta": "6967ef478d23a7e42eb8d490a38cda4f",
    "url": "f76bae21f8ea04facdb544655745c924"
  },
  {
    "meta": "c5a81e89d4e60b2bfba66a7c4dc6a636",
    "url": "c2a340b85102725118e3449741d7b551"
  },
  ...
]
```

## `/v1/posts/suggest`

Returns a list of popular tags and recommended tags for a given URL. Popular tags are tags used site-wide for the url; recommended tags are drawn from the user's own tags.

This method is intended to provide suggestions for tagging a particular url.

### Arguments

- `&url={URL}` (required) — URL for which you’d like suggestions.

### Examples

#### XML

```shell
$ curl -H Authorization:'Bearer <TOKEN>' 'https://api.ln.ht/v1/posts/suggest?url=https%3A%2F%2Fsourcehut.org%2F'
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<suggest>
    <popular>software</popular>
    <popular>collaboration</popular>
    <popular>oss</popular>
    <popular>open-source</popular>
    <recommended>development</recommended>
    <recommended>git</recommended>
    <recommended>tool</recommended>
</suggest>
```

#### JSON

```shell
$ curl -H Accept:'application/json' -H Authorization:'Bearer <TOKEN>' 'https://api.ln.ht/v1/posts/suggest?url=https%3A%2F%2Fsourcehut.org%2F'
```

```json
[
  {
    "popular": [
      "software",
      "collaboration",
      "oss",
      "open-source"
    ]
  },
  {
    "recommended": [
      "development",
      "git",
      "tool"
    ]
  }
]
```
