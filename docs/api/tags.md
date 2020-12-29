# Tags

## `/v1/tags/get`

Returns a list of tags and number of times used by a user.

### Example Response

```xml
<?xml version="1.0" encoding="UTF-8"?>
<tags>
    <tag count="5" tag="collaboration"/>
    <tag count="4" tag="development"/>
    <tag count="3" tag="git"/>
    <tag count="1" tag="open-source"/>
    <tag count="1" tag="software"/>
</tags>
```

## `/v1/tags/delete`

Delete an existing tag from all posts

### Arguments

- `&tag={TAG}` (required) — Tag to delete.

### Example Response

```xml
<result>done</result>
```

## `/v1/tags/rename`

Rename an existing tag with a new tag name.

### Arguments

- `&old={TAG}` (required) — Tag to rename.
- `&new={TAG}` (required) — New tag name.

### Example Response

```xml
<result>done</result>
```
