# Overview

The linkhut API is a way to interact programmatically with your bookmarks, notes and other linkhut data.

Wherever possible the linkhut API uses the same syntax and method names as the [Pinboard API](https://www.pinboard.in/api/).

All API methods are GET requests, even when good REST habits suggest they should use a different verb.

Methods return data in XML format or JSON format based on the value of the `Accept` header or from the value of the 
`_format` request parameter.

# Etiquette

* Please wait **at least one second** between HTTP queries, or you are likely to get automatically throttled. If you are releasing a library to access the API, you **must** do this.
* Please watch for 500 or 999 errors and back-off appropriately. It means that you have been throttled.
* Please set your User-Agent to something identifiable. The default identifiers (e.g.: `Java/1.8.0_191`, `lwp-perl`) tend to get banned from time to time.
* If you are releasing software, or a service for other people to use, your software or service **must not** add any links without a user’s explicit direction. Likewise, you **must not** modify any urls except under the user’s explicit direction.