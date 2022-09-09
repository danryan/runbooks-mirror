{
  policy: {
    phases: {
      hot: {
        actions: {
          rollover: {
            max_age: '6d',
            max_primary_shard_size: '5gb',
          },
          set_priority: {
            priority: 100,
          },
        },
      },
      warm: {
        actions: {
          allocate: {
            require: {
              data: null,
            },
            total_shards_per_node: 3,
          },
          set_priority: {
            priority: 50,
          },
        },
      },
      delete: {
        min_age: '5d',
        actions: {
          delete: {},
        },
      },
    },
  },
}
