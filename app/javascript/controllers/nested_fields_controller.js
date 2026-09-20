import { Controller } from "@hotwired/stimulus"

// Adds and removes the nested serving rows on the food form. No gem and no
// CDN: the blank row lives in a <template>, whose contents are inert until
// they are copied into the form, so an unused row is never submitted.
export default class extends Controller {
  static targets = ["list", "template", "item"]

  add() {
    const html = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, new Date().getTime())
    this.listTarget.insertAdjacentHTML("beforeend", html)
  }

  // A saved row must be SUBMITTED as removed — accepts_nested_attributes_for
  // on Food is declared with allow_destroy, and that is the only thing that
  // deletes it; dropping the row from the DOM would just leave it in the
  // database. A row that was never saved has nothing to tell the server
  // about, so it goes away entirely.
  remove(event) {
    const row = event.target.closest("[data-nested-fields-target='item']")
    if (!row) return

    const destroy = row.querySelector("input[name$='[_destroy]']")
    if (destroy) {
      destroy.value = "1"
      // The hidden attribute, not a class: the row must keep posting its id
      // and its _destroy flag while staying out of the layout.
      row.hidden = true
    } else {
      row.remove()
    }
  }
}
