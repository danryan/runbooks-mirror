{
  policy: {
    phases: {
      hot: {
        actions: {
          rollover: {
            max_age: '30d',
            max_size: '20gb',
          },
          set_priority: {
            priority: 100,
          },
        },
      },
      delete: {
        min_age: '360d',
        actions: {
          delete: {},
        },
      },
    },
  },
}
