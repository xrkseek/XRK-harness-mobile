// A local xrk-mobile plugin. Runs inside the XRK engine (Node); the xrk-mobile app draws
// what package.json "xrkGo" declares and calls these handlers when tapped.
export const name = 'local-my-plugin'

export function apply(ctx) {
  // Runs only on hosts with the xrk-mobile bridge. Write ['xrkGo'], never ['xrkGo?'].
  ctx.inject(['xrkGo'], (ctx) => {
    ctx.xrkGo.on('paste-quote', (scope, event) => {
      const zh = !String(event.locale).startsWith('en')
      const text = (scope.clipboard ?? '').trim()
      if (text === '') return { toast: zh ? '剪贴板里没有文字' : 'The clipboard is empty' }
      const quoted = text.split('\n').map((line) => `> ${line}`).join('\n')
      return { insert: `${quoted}\n\n`.slice(0, 2000) }
    })
  })
}
