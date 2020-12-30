# Tags

## `/v1/tags/get`

Returns a list of tags and number of times used by a user.

### Examples

#### XML

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

#### JSON

```json
{
  "collaboration": 5,
  "development": 4,
  "git": 3,
  "open-source": 1,
  "software": 1
}
```

## `/v1/tags/delete`

Delete an existing tag from all posts

### Arguments

- `&tag={TAG}` (required) — Tag to delete.

### Examples

#### XML

```xml
<result>done</result>
```

#### JSON

```json
{"result_code":"done"}
```

## `/v1/tags/rename`

Rename an existing tag with a new tag name.

### Arguments

- `&old={TAG}` (required) — Tag to rename.
- `&new={TAG}` (required) — New tag name.

### Examples

#### XML

```xml
<result>done</result>
```

#### JSON

```json
{"result_code":"done"}
```