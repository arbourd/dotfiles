module.exports = {
  config: {
    fontSize: 14,
    fontFamily: '"Source Code Pro Medium", Menlo, "DejaVu Sans Mono", Consolas, "Lucida Console", monospace',
    cursorColor: 'rgba(255,255,255,0.5)',
    cursorShape: 'UNDERLINE',
    cursorBlink: true,
    foregroundColor: '#839496',
    backgroundColor: '#002833',
    borderColor: '#999',
    css: '',
    termCSS: '',
    showHamburgerMenu: '',
    showWindowControls: '',
    padding: '12px 14px',
    colors: {
      black: '#003541',
      red: '#dc322f',
      green: '#859901',
      yellow: '#b58901',
      blue: '#268bd2',
      magenta: '#d33682',
      cyan: '#2aa198',
      white: '#eee8d5',
      lightBlack: '#002833',
      lightRed: '#cb4b16',
      lightGreen: '#586e75',
      lightYellow: '#657b83',
      lightBlue: '#839496',
      lightMagenta: '#6c6ec6',
      lightCyan: '#93a1a1',
      lightWhite: '#fdf6e3'
    },
    shell: '/usr/local/bin/fish',
    shellArgs: ['--login'],
    env: {},
    bell: 'SOUND',
    copyOnSelect: false
  },
  plugins: [
    'hypercwd'
  ],
  localPlugins: []
};
