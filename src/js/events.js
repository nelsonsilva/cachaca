module.exports = function() {

/**
 * An event source can dispatch events. These are dispatched to all of the
 * functions listening for that event type with arguments.
 * @constructor
 */
function EventSource() {
  this.listeners_ = {};
};

EventSource.prototype = {
  /**
   * Add |callback| as a listener for |type| events.
   * @param {string} type The type of the event.
   * @param {function(Object|undefined): boolean} callback The function to call
   *     when this event type is dispatched. Arguments depend on the event
   *     source and type. The function returns whether the event was "handled"
   *     which will prevent delivery to the rest of the listeners.
   */
  addEventListener: function(type, callback) {
    if (!this.listeners_[type])
      this.listeners_[type] = [];
    this.listeners_[type].push(callback);
  },

  /**
   * Remove |callback| as a listener for |type| events.
   * @param {string} type The type of the event.
   * @param {function(Object|undefined): boolean} callback The callback
   *     function to remove from the event listeners for events having type
   *     |type|.
   */
  removeEventListener: function(type, callback) {
    if (!this.listeners_[type])
      return;
    for (var i = this.listeners_[type].length - 1; i >= 0; i--) {
      if (this.listeners_[type][i] == callback) {
        this.listeners_[type].splice(i, 1);
      }
    }
  },

  /**
   * Dispatch an event to all listeners for events of type |type|.
   * @param {type} type The type of the event being dispatched.
   * @param {...Object} var_args The arguments to pass when calling the
   *     callback function.
   * @return {boolean} Returns true if the event was handled.
   */
  dispatchEvent: function(type, var_args) {
    if (!this.listeners_[type])
      return false;
    for (var i = 0; i < this.listeners_[type].length; i++) {
      if (this.listeners_[type][i].apply(
              /* this */ null,
              /* var_args */ Array.prototype.slice.call(arguments, 1))) {
        return true;
      }
    }
  }
};

return { 'EventSource' : EventSource};
}();