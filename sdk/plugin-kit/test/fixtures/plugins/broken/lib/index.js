export const name = 'broken-demo'
export const inject = ['xrkGo']
export function apply(ctx) {
  ctx.inject(['xrkGo?'], (ctx) => {
    ctx.xrkGo.on('a', () => ({ insert: 'x' }))
  })
}
