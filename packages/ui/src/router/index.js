import { createRouter, createWebHashHistory } from 'vue-router'
import Home from '../views/App.vue'
import MainContent from '../views/MainContent.vue'
import InitGame from '../views/InitGame.vue'
import Disclaimer from '../views/GameDisclaimer.vue'
import Instructions from '../views/GameInstructions.vue'
import GlobalStats from '../views/GlobalStats.vue'
import TradeHistory from '../views/TradeHistory.vue'
import { useStore } from '@/stores/player'
import { createApp } from 'vue'
import ScanId from '../views/ScanId.vue'
import App from '@/App.vue'
import { createPinia } from 'pinia'

export const pinia = createPinia()

const app = createApp(App)
app.use(pinia)

const routes = [
  {
    path: '/',
    name: 'home',
    component: Home,
    beforeEnter: async (to, from, next) => {
      const store = useStore()
      const loginInfo = store.getToken()
      if (loginInfo && loginInfo.token) {
        next({ name: 'main', params: { id: loginInfo.key } })
      } else {
        next('init-game')
      }
    }
  },
  {
    name: 'disclaimer',
    path: '/disclaimer',
    component: Disclaimer
  },
  {
    name: 'main',
    path: '/:id',
    component: MainContent
  },
  {
    name: 'init-game',
    path: '/init-game',
    component: InitGame,
    beforeEnter: async (to, from, next) => {
      const store = useStore()
      const loginInfo = store.getToken()
      const claimedPlayerError =
        store.errors.info &&
        store.errors.info.includes('Player has not been claimed yet')
      const error = store.errors.info
      if (loginInfo && claimedPlayerError) {
        store.clearTokenInfo()
      }
      if (loginInfo && loginInfo.token && !error) {
        next({ name: 'main', params: { id: loginInfo.key } })
      } else {
        next()
      }
    }
  },
  {
    name: 'scan',
    path: '/scan',
    component: ScanId
  },
  {
    name: 'stats',
    path: '/stats',
    component: GlobalStats
  },
  {
    name: 'tradeHistory',
    path: '/trades',
    component: TradeHistory
  },
  {
    name: 'instructions',
    path: '/instructions',
    component: Instructions
  },
  {
    name: 'import',
    path: '/import',
    beforeEnter: (to, from, next) => {
      const { username, token, key } = to.query

      if (!username || !token || !key) {
        next('/')
      } else {
        localStorage.setItem(
          'tokenInfo',
          JSON.stringify({ username, token, key })
        )

        next(`/${key}`)
      }
    }
  }
]

const router = createRouter({
  history: createWebHashHistory(),
  routes
})

router.beforeEach(to => {
  const playerStore = useStore()

  if (to.meta.requiresAuth && !playerStore.isLoggedIn) return '/login'
})

export default router
