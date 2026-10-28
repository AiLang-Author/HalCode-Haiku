# BMessage Field Type Reference

Complete Add/Find/Replace/Has method table and type_code constants.

## Type Codes

| Constant | Description |
|----------|-------------|
| `B_BOOL_TYPE` | Boolean |
| `B_INT8_TYPE` | 8-bit signed integer |
| `B_UINT8_TYPE` | 8-bit unsigned integer |
| `B_INT16_TYPE` | 16-bit signed integer |
| `B_UINT16_TYPE` | 16-bit unsigned integer |
| `B_INT32_TYPE` | 32-bit signed integer |
| `B_UINT32_TYPE` | 32-bit unsigned integer |
| `B_INT64_TYPE` | 64-bit signed integer |
| `B_UINT64_TYPE` | 64-bit unsigned integer |
| `B_FLOAT_TYPE` | 32-bit float |
| `B_DOUBLE_TYPE` | 64-bit double |
| `B_STRING_TYPE` | NUL-terminated string |
| `B_POINT_TYPE` | BPoint (float x, float y) |
| `B_RECT_TYPE` | BRect (float left, top, right, bottom) |
| `B_SIZE_TYPE` | BSize (float width, float height) |
| `B_RGB_32_BIT_TYPE` | rgb_color (uint8 red, green, blue, alpha) |
| `B_POINTER_TYPE` | void pointer (local only — not flattenable) |
| `B_MESSENGER_TYPE` | BMessenger |
| `B_REF_TYPE` | entry_ref (dev_t device, ino_t directory, const char *name) |
| `B_NODE_REF_TYPE` | node_ref (dev_t device, ino_t node) |
| `B_MESSAGE_TYPE` | Nested BMessage |
| `B_ANY_TYPE` | Wildcard for queries |
| `B_MIME_TYPE` | MIME string |
| `B_RAW_TYPE` | Raw byte data |

---

## Add Methods

All return `status_t` (`B_OK` on success).

### Scalar Types
```cpp
status_t AddBool(const char *name, bool value)
status_t AddInt8(const char *name, int8 value)
status_t AddUInt8(const char *name, uint8 value)
status_t AddInt16(const char *name, int16 value)
status_t AddUInt16(const char *name, uint16 value)
status_t AddInt32(const char *name, int32 value)
status_t AddUInt32(const char *name, uint32 value)
status_t AddInt64(const char *name, int64 value)
status_t AddUInt64(const char *name, uint64 value)
status_t AddFloat(const char *name, float value)
status_t AddDouble(const char *name, double value)
```

### String
```cpp
status_t AddString(const char *name, const char *string)
status_t AddString(const char *name, const BString &string)
```

### Geometry
```cpp
status_t AddPoint(const char *name, BPoint point)
status_t AddRect(const char *name, BRect rect)
status_t AddSize(const char *name, BSize size)
status_t AddAlignment(const char *name, const BAlignment &alignment)
```

### Color
```cpp
status_t AddColor(const char *name, rgb_color value)
```

### Reference Types
```cpp
status_t AddPointer(const char *name, const void *pointer)
status_t AddMessenger(const char *name, BMessenger messenger)
status_t AddRef(const char *name, const entry_ref *ref)
status_t AddNodeRef(const char *name, const node_ref *ref)
status_t AddMessage(const char *name, const BMessage *message)
```

### Generic / Flattenable
```cpp
status_t AddFlat(const char *name, BFlattenable *object, int32 count = 1)
status_t AddFlat(const char *name, const BFlattenable *object, int32 count = 1)
status_t AddData(const char *name, type_code type, const void *data,
                 ssize_t numBytes, bool isFixedSize = true, int32 count = 1)
```

---

## Find Methods

All return `status_t` (`B_OK`, `B_NAME_NOT_FOUND`, or `B_BAD_INDEX`).
Each has a single-value form and an indexed form for arrays.

### Scalar Types
```cpp
status_t FindBool(const char *name, bool *value) const
status_t FindBool(const char *name, int32 index, bool *value) const
status_t FindInt8(const char *name, int8 *value) const
status_t FindInt8(const char *name, int32 index, int8 *value) const
status_t FindUInt8(const char *name, uint8 *value) const
status_t FindUInt8(const char *name, int32 index, uint8 *value) const
status_t FindInt16(const char *name, int16 *value) const
status_t FindInt16(const char *name, int32 index, int16 *value) const
status_t FindUInt16(const char *name, uint16 *value) const
status_t FindUInt16(const char *name, int32 index, uint16 *value) const
status_t FindInt32(const char *name, int32 *value) const
status_t FindInt32(const char *name, int32 index, int32 *value) const
status_t FindUInt32(const char *name, uint32 *value) const
status_t FindUInt32(const char *name, int32 index, uint32 *value) const
status_t FindInt64(const char *name, int64 *value) const
status_t FindInt64(const char *name, int32 index, int64 *value) const
status_t FindUInt64(const char *name, uint64 *value) const
status_t FindUInt64(const char *name, int32 index, uint64 *value) const
status_t FindFloat(const char *name, float *value) const
status_t FindFloat(const char *name, int32 index, float *value) const
status_t FindDouble(const char *name, double *value) const
status_t FindDouble(const char *name, int32 index, double *value) const
```

### String
```cpp
status_t FindString(const char *name, const char **string) const
status_t FindString(const char *name, int32 index, const char **string) const
status_t FindString(const char *name, BString *string) const
status_t FindString(const char *name, int32 index, BString *string) const
```

### Geometry
```cpp
status_t FindPoint(const char *name, BPoint *point) const
status_t FindPoint(const char *name, int32 index, BPoint *point) const
status_t FindRect(const char *name, BRect *rect) const
status_t FindRect(const char *name, int32 index, BRect *rect) const
status_t FindSize(const char *name, BSize *size) const
status_t FindSize(const char *name, int32 index, BSize *size) const
status_t FindAlignment(const char *name, BAlignment *alignment) const
status_t FindAlignment(const char *name, int32 index, BAlignment *alignment) const
```

### Color
```cpp
status_t FindColor(const char *name, rgb_color *value) const
status_t FindColor(const char *name, int32 index, rgb_color *value) const
```

### Reference Types
```cpp
status_t FindPointer(const char *name, void **pointer) const
status_t FindPointer(const char *name, int32 index, void **pointer) const
status_t FindMessenger(const char *name, BMessenger *messenger) const
status_t FindMessenger(const char *name, int32 index, BMessenger *messenger) const
status_t FindRef(const char *name, entry_ref *ref) const
status_t FindRef(const char *name, int32 index, entry_ref *ref) const
status_t FindNodeRef(const char *name, node_ref *ref) const
status_t FindNodeRef(const char *name, int32 index, node_ref *ref) const
status_t FindMessage(const char *name, BMessage *message) const
status_t FindMessage(const char *name, int32 index, BMessage *message) const
```

### Generic / Flattenable
```cpp
status_t FindFlat(const char *name, BFlattenable *object) const
status_t FindFlat(const char *name, int32 index, BFlattenable *object) const
status_t FindData(const char *name, type_code type,
                  const void **data, ssize_t *numBytes) const
status_t FindData(const char *name, type_code type, int32 index,
                  const void **data, ssize_t *numBytes) const
```

---

## Replace Methods

All return `status_t`. The named field must already exist (added via Add*).
Each has a single-value form and an indexed form.

### Scalar Types
```cpp
status_t ReplaceBool(const char *name, bool value)
status_t ReplaceBool(const char *name, int32 index, bool value)
status_t ReplaceInt8(const char *name, int8 value)
status_t ReplaceInt8(const char *name, int32 index, int8 value)
status_t ReplaceUInt8(const char *name, uint8 value)
status_t ReplaceUInt8(const char *name, int32 index, uint8 value)
status_t ReplaceInt16(const char *name, int16 value)
status_t ReplaceInt16(const char *name, int32 index, int16 value)
status_t ReplaceUInt16(const char *name, uint16 value)
status_t ReplaceUInt16(const char *name, int32 index, uint16 value)
status_t ReplaceInt32(const char *name, int32 value)
status_t ReplaceInt32(const char *name, int32 index, int32 value)
status_t ReplaceUInt32(const char *name, uint32 value)
status_t ReplaceUInt32(const char *name, int32 index, uint32 value)
status_t ReplaceInt64(const char *name, int64 value)
status_t ReplaceInt64(const char *name, int32 index, int64 value)
status_t ReplaceUInt64(const char *name, uint64 value)
status_t ReplaceUInt64(const char *name, int32 index, uint64 value)
status_t ReplaceFloat(const char *name, float value)
status_t ReplaceFloat(const char *name, int32 index, float value)
status_t ReplaceDouble(const char *name, double value)
status_t ReplaceDouble(const char *name, int32 index, double value)
```

### String
```cpp
status_t ReplaceString(const char *name, const char *string)
status_t ReplaceString(const char *name, int32 index, const char *string)
status_t ReplaceString(const char *name, const BString &string)
status_t ReplaceString(const char *name, int32 index, const BString &string)
```

### Geometry
```cpp
status_t ReplacePoint(const char *name, BPoint point)
status_t ReplacePoint(const char *name, int32 index, BPoint point)
status_t ReplaceRect(const char *name, BRect rect)
status_t ReplaceRect(const char *name, int32 index, BRect rect)
status_t ReplaceSize(const char *name, BSize size)
status_t ReplaceSize(const char *name, int32 index, BSize size)
status_t ReplaceAlignment(const char *name, const BAlignment &alignment)
status_t ReplaceAlignment(const char *name, int32 index, const BAlignment &alignment)
```

### Color
```cpp
status_t ReplaceColor(const char *name, rgb_color value)
status_t ReplaceColor(const char *name, int32 index, rgb_color value)
```

### Reference Types
```cpp
status_t ReplacePointer(const char *name, const void *pointer)
status_t ReplacePointer(const char *name, int32 index, const void *pointer)
status_t ReplaceMessenger(const char *name, BMessenger messenger)
status_t ReplaceMessenger(const char *name, int32 index, BMessenger messenger)
status_t ReplaceRef(const char *name, const entry_ref *ref)
status_t ReplaceRef(const char *name, int32 index, const entry_ref *ref)
status_t ReplaceNodeRef(const char *name, const node_ref *ref)
status_t ReplaceNodeRef(const char *name, int32 index, const node_ref *ref)
status_t ReplaceMessage(const char *name, const BMessage *message)
status_t ReplaceMessage(const char *name, int32 index, const BMessage *message)
```

### Generic / Flattenable
```cpp
status_t ReplaceFlat(const char *name, BFlattenable *object)
status_t ReplaceFlat(const char *name, int32 index, BFlattenable *object)
status_t ReplaceData(const char *name, type_code type,
                     const void *data, ssize_t numBytes)
status_t ReplaceData(const char *name, type_code type, int32 index,
                     const void *data, ssize_t numBytes)
```

---

## Has Methods

Check whether a named field exists, optionally at a given index.

```cpp
bool HasBool(const char *name, int32 index = 0) const
bool HasInt8(const char *name, int32 index = 0) const
bool HasUInt8(const char *name, int32 index = 0) const
bool HasInt16(const char *name, int32 index = 0) const
bool HasUInt16(const char *name, int32 index = 0) const
bool HasInt32(const char *name, int32 index = 0) const
bool HasUInt32(const char *name, int32 index = 0) const
bool HasInt64(const char *name, int32 index = 0) const
bool HasUInt64(const char *name, int32 index = 0) const
bool HasFloat(const char *name, int32 index = 0) const
bool HasDouble(const char *name, int32 index = 0) const
bool HasString(const char *name, int32 index = 0) const
bool HasPoint(const char *name, int32 index = 0) const
bool HasRect(const char *name, int32 index = 0) const
bool HasSize(const char *name, int32 index = 0) const
bool HasAlignment(const char *name, int32 index = 0) const
bool HasColor(const char *name, int32 index = 0) const
bool HasPointer(const char *name, int32 index = 0) const
bool HasMessenger(const char *name, int32 index = 0) const
bool HasRef(const char *name, int32 index = 0) const
bool HasNodeRef(const char *name, int32 index = 0) const
bool HasMessage(const char *name, int32 index = 0) const
bool HasFlat(const char *name, const BFlattenable *object) const
bool HasFlat(const char *name, int32 index, const BFlattenable *object) const
bool HasData(const char *name, type_code type, int32 index = 0) const
```

---

## Inspection

```cpp
int32    CountNames(type_code type) const  // B_ANY_TYPE for all
status_t GetInfo(type_code typeRequested, int32 index,
                 char **nameFound, type_code *typeFound,
                 int32 *countFound = NULL) const
status_t GetInfo(const char *name, type_code *typeFound,
                 int32 *countFound = NULL) const
```

## Removal

```cpp
status_t RemoveData(const char *name, int32 index = 0)  // one entry
status_t RemoveName(const char *name)                    // all entries for name
status_t MakeEmpty()                                      // clear everything
```
