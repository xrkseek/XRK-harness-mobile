/// Face `settings.describe` → `permission` namespace (Host FACE_PERMISSION_SCHEMA).
Map<String, Object?> facePermissionSchema() => {
      'uid': 8,
      'refs': {
        '1': {'type': 'const', 'meta': {'description': 'Read only'}, 'value': 'read-only'},
        '2': {'type': 'const', 'meta': {'description': 'Workspace write'}, 'value': 'workspace-write'},
        '3': {'type': 'const', 'meta': {'description': 'Full access'}, 'value': 'danger-full-access'},
        '4': {'type': 'const', 'meta': {'description': 'Auto review'}, 'value': 'auto'},
        '5': {
          'type': 'union',
          'list': [1, 2, 3, 4],
        },
        '6': {'type': 'string'},
        '7': {'type': 'array', 'inner': 6},
        '8': {
          'type': 'object',
          'dict': {'defaultPreset': 5, 'extraWritableRoots': 7},
        },
      },
    };

Map<String, Object?> facePermissionDescribe({
  String defaultPreset = 'workspace-write',
  int revision = 7,
  bool writable = true,
}) =>
    {
      'writable': writable,
      'namespaces': [
        {
          'ns': 'permission',
          'value': {'defaultPreset': defaultPreset},
          'revision': revision,
          'schema': facePermissionSchema(),
        },
      ],
    };
