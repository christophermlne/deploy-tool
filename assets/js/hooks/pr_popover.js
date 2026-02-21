// PR Popover Hook
// Shows a GitHub-style popover with PR details on hover over pr_link elements.

const prCache = new Map()
let popoverEl = null
let hideTimeout = null
let activeHook = null

function getOrCreatePopover() {
  if (popoverEl) return popoverEl

  popoverEl = document.createElement("div")
  popoverEl.className = [
    "fixed z-50 bg-white rounded-lg shadow-lg border border-gray-200",
    "w-80 text-sm opacity-0 pointer-events-none transition-opacity duration-150"
  ].join(" ")
  popoverEl.style.maxWidth = "320px"

  popoverEl.addEventListener("mouseenter", () => {
    clearTimeout(hideTimeout)
  })
  popoverEl.addEventListener("mouseleave", () => {
    scheduleHide()
  })

  document.body.appendChild(popoverEl)
  return popoverEl
}

function positionPopover(anchor) {
  const el = getOrCreatePopover()
  const rect = anchor.getBoundingClientRect()
  const popoverHeight = el.offsetHeight || 200

  // Position above by default, below if not enough space
  let top = rect.top - popoverHeight - 8
  if (top < 8) {
    top = rect.bottom + 8
  }

  let left = rect.left
  // Keep within viewport horizontally
  if (left + 320 > window.innerWidth - 8) {
    left = window.innerWidth - 328
  }

  el.style.top = `${top}px`
  el.style.left = `${left}px`
}

function showPopover(anchor) {
  const el = getOrCreatePopover()
  clearTimeout(hideTimeout)

  el.classList.remove("opacity-0", "pointer-events-none")
  el.classList.add("opacity-100", "pointer-events-auto")

  positionPopover(anchor)
}

function scheduleHide() {
  hideTimeout = setTimeout(() => {
    if (!popoverEl) return
    popoverEl.classList.remove("opacity-100", "pointer-events-auto")
    popoverEl.classList.add("opacity-0", "pointer-events-none")
    activeHook = null
  }, 200)
}

function renderLoading() {
  const el = getOrCreatePopover()
  el.innerHTML = `
    <div class="p-4">
      <div class="animate-pulse space-y-3">
        <div class="h-3 bg-gray-200 rounded w-1/3"></div>
        <div class="h-4 bg-gray-200 rounded w-3/4"></div>
        <div class="h-5 bg-gray-200 rounded w-1/4"></div>
        <div class="h-3 bg-gray-200 rounded w-full"></div>
        <div class="h-3 bg-gray-200 rounded w-2/3"></div>
      </div>
    </div>
  `
}

function renderError(error) {
  const el = getOrCreatePopover()
  el.innerHTML = `
    <div class="p-4 text-gray-500 text-center">
      <p>Failed to load PR details</p>
    </div>
  `
}

function statusBadge(state, isDraft) {
  if (isDraft) {
    return `<span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-700">Draft</span>`
  }
  const styles = {
    MERGED: "bg-purple-100 text-purple-800",
    OPEN: "bg-green-100 text-green-800",
    CLOSED: "bg-red-100 text-red-800"
  }
  const icons = {
    MERGED: `<svg class="w-3 h-3 mr-1" fill="currentColor" viewBox="0 0 16 16"><path d="M5.45 5.154A4.25 4.25 0 004.75 6.5a4.25 4.25 0 001.35 3.098A.75.75 0 015 10.75v3.5a.75.75 0 01-1.5 0v-3.034a5.75 5.75 0 01.17-8.716.75.75 0 011.28.53v2.22a.75.75 0 01-1.5 0zm6.6 4.692A4.25 4.25 0 0012.75 6.5a4.25 4.25 0 00-1.35-3.098A.75.75 0 0112.5 2.25V.75a.75.75 0 011.28-.53 5.75 5.75 0 01.17 8.716v3.314a.75.75 0 01-1.5 0v-2.22a.75.75 0 01-.1-.378z"/></svg>`,
    OPEN: `<svg class="w-3 h-3 mr-1" fill="currentColor" viewBox="0 0 16 16"><circle cx="8" cy="8" r="7" fill="none" stroke="currentColor" stroke-width="2"/></svg>`,
    CLOSED: `<svg class="w-3 h-3 mr-1" fill="currentColor" viewBox="0 0 16 16"><path d="M11.28 6.78a.75.75 0 00-1.06-1.06L7.25 8.69 5.78 7.22a.75.75 0 00-1.06 1.06l2 2a.75.75 0 001.06 0l3.5-3.5z"/><path fill-rule="evenodd" d="M16 8A8 8 0 110 8a8 8 0 0116 0zm-1.5 0a6.5 6.5 0 11-13 0 6.5 6.5 0 0113 0z"/></svg>`
  }
  const labels = { MERGED: "Merged", OPEN: "Open", CLOSED: "Closed" }
  const style = styles[state] || styles.CLOSED
  const icon = icons[state] || ""
  const label = labels[state] || state

  return `<span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${style}">${icon}${label}</span>`
}

function formatDate(dateStr) {
  const date = new Date(dateStr)
  return date.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })
}

function truncateRef(ref, maxLen = 20) {
  return ref.length > maxLen ? ref.slice(0, maxLen) + "\u2026" : ref
}

function renderReviews(reviews) {
  if (!reviews || reviews.length === 0) return ""

  const approved = reviews.filter(r => r.state === "APPROVED")
  const changesRequested = reviews.filter(r => r.state === "CHANGES_REQUESTED")

  const lines = []

  if (approved.length > 0) {
    const names = approved.map(r => r.author).join(", ")
    lines.push(`
      <div class="flex items-center gap-1.5 text-green-700">
        <svg class="w-4 h-4 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
          <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.857-9.809a.75.75 0 00-1.214-.882l-3.483 4.79-1.88-1.88a.75.75 0 10-1.06 1.061l2.5 2.5a.75.75 0 001.137-.089l4-5.5z" clip-rule="evenodd" />
        </svg>
        <span>Approved by ${names}</span>
      </div>
    `)
  }

  if (changesRequested.length > 0) {
    const names = changesRequested.map(r => r.author).join(", ")
    lines.push(`
      <div class="flex items-center gap-1.5 text-red-700">
        <svg class="w-4 h-4 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
          <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z" clip-rule="evenodd" />
        </svg>
        <span>Changes requested by ${names}</span>
      </div>
    `)
  }

  return lines.length > 0 ? `<div class="space-y-1">${lines.join("")}</div>` : ""
}

function renderPopoverContent(data) {
  const el = getOrCreatePopover()

  if (data.error) {
    renderError(data.error)
    return
  }

  const reviewsHtml = renderReviews(data.reviews)
  const bodyHtml = data.body
    ? `<p class="text-gray-600 text-xs mt-2 line-clamp-3">${escapeHtml(data.body)}</p>`
    : ""

  el.innerHTML = `
    <div class="p-4 space-y-3">
      <div>
        <div class="text-xs text-gray-500">${escapeHtml(data.author)} on ${formatDate(data.created_at)}</div>
        <div class="font-semibold text-gray-900 mt-0.5 leading-snug">
          ${escapeHtml(data.title)} <span class="font-normal text-gray-500">#${data.number}</span>
        </div>
      </div>

      <div>${statusBadge(data.state, data.is_draft)}</div>

      ${bodyHtml}

      <div class="flex items-center gap-1.5 text-xs">
        <span class="px-2 py-0.5 bg-gray-100 rounded-full text-gray-700 font-mono truncate max-w-[140px]" title="${escapeHtml(data.base_ref)}">${escapeHtml(truncateRef(data.base_ref))}</span>
        <svg class="w-3 h-3 text-gray-400 flex-shrink-0" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M10 19l-7-7m0 0l7-7m-7 7h18"/></svg>
        <span class="px-2 py-0.5 bg-gray-100 rounded-full text-gray-700 font-mono truncate max-w-[140px]" title="${escapeHtml(data.head_ref)}">${escapeHtml(truncateRef(data.head_ref))}</span>
      </div>

      ${reviewsHtml ? `<div class="border-t border-gray-100 pt-2 text-xs">${reviewsHtml}</div>` : ""}
    </div>
  `

  // Reposition after content renders (height may have changed)
  if (activeHook) {
    requestAnimationFrame(() => positionPopover(activeHook))
  }
}

function escapeHtml(text) {
  if (!text) return ""
  const div = document.createElement("div")
  div.textContent = text
  return div.innerHTML
}

// Listen for pr_info events pushed from the server
window.addEventListener("phx:pr_info", (e) => {
  const data = e.detail
  const key = String(data.pr_number)

  if (!data.error) {
    prCache.set(key, data)
  }

  // Only update popover if it's still showing for this PR
  if (activeHook && activeHook.dataset.prNumber === key) {
    renderPopoverContent(data)
  }
})

export const PRPopover = {
  mounted() {
    this.el.addEventListener("mouseenter", () => {
      const prNumber = this.el.dataset.prNumber
      activeHook = this.el
      renderLoading()
      showPopover(this.el)

      if (prCache.has(prNumber)) {
        renderPopoverContent(prCache.get(prNumber))
      } else {
        this.pushEvent("fetch_pr_info", { pr_number: parseInt(prNumber) })
      }
    })

    this.el.addEventListener("mouseleave", () => {
      scheduleHide()
    })
  }
}
