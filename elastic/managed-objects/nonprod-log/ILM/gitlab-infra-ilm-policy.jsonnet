{
  policy: {
    phases: {
      hot: {
        actions: {
          rollover: {
            max_size: '15gb',
          },
        },
      },
      delete: {
        min_age: '7d',
        actions: {
          delete: {},
        },
      },
    },
  },
}
