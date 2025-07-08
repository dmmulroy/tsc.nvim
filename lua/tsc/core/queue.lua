---@class tsc.Queue
---@field private _items table<number, any> The queue items
---@field private _priorities table<number, number> Priority values for items
---@field private _metadata table<number, table> Metadata for items
---@field private _size number Current size of the queue
---@field private _strategy string Queue strategy (priority|size|alpha|fifo)
---@field private _comparator function Comparison function for ordering
local Queue = {}
Queue.__index = Queue

---@class QueueItem
---@field id string Unique identifier
---@field data any The actual item data
---@field priority number Priority value (higher = more important)
---@field metadata table Additional metadata

---@class QueueOptions
---@field strategy? string Queue ordering strategy
---@field comparator? function Custom comparison function

---Create a new queue instance
---@param opts? QueueOptions
---@return tsc.Queue
function Queue.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Queue)
  
  self._items = {}
  self._priorities = {}
  self._metadata = {}
  self._size = 0
  self._strategy = opts.strategy or "fifo"
  
  -- Set up comparator based on strategy
  if opts.comparator then
    self._comparator = opts.comparator
  else
    self._comparator = self:_get_default_comparator()
  end
  
  return self
end

---Get the default comparator for the current strategy
---@return function
function Queue:_get_default_comparator()
  local strategies = {
    -- First in, first out
    fifo = function(a, b)
      return a.index < b.index
    end,
    
    -- Last in, first out
    lifo = function(a, b)
      return a.index > b.index
    end,
    
    -- Higher priority first
    priority = function(a, b)
      if a.priority == b.priority then
        return a.index < b.index -- FIFO for same priority
      end
      return a.priority > b.priority
    end,
    
    -- Smaller items first (based on metadata.size)
    size = function(a, b)
      local size_a = a.metadata.size or 0
      local size_b = b.metadata.size or 0
      if size_a == size_b then
        return a.index < b.index
      end
      return size_a < size_b
    end,
    
    -- Alphabetical by metadata.name
    alpha = function(a, b)
      local name_a = a.metadata.name or ""
      local name_b = b.metadata.name or ""
      if name_a == name_b then
        return a.index < b.index
      end
      return name_a < name_b
    end
  }
  
  return strategies[self._strategy] or strategies.fifo
end

---Add an item to the queue
---@param item any The item to add
---@param priority? number Priority (default 0)
---@param metadata? table Additional metadata
---@return string id The item's unique ID
function Queue:push(item, priority, metadata)
  self._size = self._size + 1
  local id = string.format("%d_%d", os.time(), self._size)
  
  table.insert(self._items, {
    id = id,
    data = item,
    priority = priority or 0,
    metadata = metadata or {},
    index = self._size
  })
  
  return id
end

---Add multiple items to the queue
---@param items any[] Array of items
---@param priority_fn? function Function to calculate priority for each item
---@param metadata_fn? function Function to calculate metadata for each item
---@return string[] ids Array of item IDs
function Queue:push_many(items, priority_fn, metadata_fn)
  local ids = {}
  
  for i, item in ipairs(items) do
    local priority = priority_fn and priority_fn(item, i) or 0
    local metadata = metadata_fn and metadata_fn(item, i) or {}
    local id = self:push(item, priority, metadata)
    table.insert(ids, id)
  end
  
  return ids
end

---Remove and return the next item from the queue
---@return any|nil item, string|nil id
function Queue:pop()
  if self._size == 0 then
    return nil, nil
  end
  
  -- Sort items according to strategy
  table.sort(self._items, function(a, b)
    return self._comparator(a, b)
  end)
  
  -- Remove and return the first item
  local item_data = table.remove(self._items, 1)
  self._size = self._size - 1
  
  return item_data.data, item_data.id
end

---Get the next item without removing it
---@return any|nil item, string|nil id
function Queue:peek()
  if self._size == 0 then
    return nil, nil
  end
  
  -- Sort items according to strategy
  table.sort(self._items, function(a, b)
    return self._comparator(a, b)
  end)
  
  local item_data = self._items[1]
  return item_data.data, item_data.id
end

---Remove multiple items from the queue
---@param count number Number of items to remove
---@return table items Array of removed items with their IDs
function Queue:pop_many(count)
  local items = {}
  
  for _ = 1, math.min(count, self._size) do
    local item, id = self:pop()
    if item then
      table.insert(items, { data = item, id = id })
    end
  end
  
  return items
end

---Get multiple items without removing them
---@param count number Number of items to peek
---@return table items Array of items with their IDs
function Queue:peek_many(count)
  if self._size == 0 then
    return {}
  end
  
  -- Sort items according to strategy
  table.sort(self._items, function(a, b)
    return self._comparator(a, b)
  end)
  
  local items = {}
  for i = 1, math.min(count, self._size) do
    local item_data = self._items[i]
    table.insert(items, {
      data = item_data.data,
      id = item_data.id
    })
  end
  
  return items
end

---Remove a specific item by ID
---@param id string The item ID to remove
---@return any|nil item The removed item, or nil if not found
function Queue:remove(id)
  for i, item_data in ipairs(self._items) do
    if item_data.id == id then
      table.remove(self._items, i)
      self._size = self._size - 1
      return item_data.data
    end
  end
  return nil
end

---Update the priority of an item
---@param id string The item ID
---@param priority number New priority value
---@return boolean success
function Queue:update_priority(id, priority)
  for _, item_data in ipairs(self._items) do
    if item_data.id == id then
      item_data.priority = priority
      return true
    end
  end
  return false
end

---Update the metadata of an item
---@param id string The item ID
---@param metadata table New metadata (merged with existing)
---@return boolean success
function Queue:update_metadata(id, metadata)
  for _, item_data in ipairs(self._items) do
    if item_data.id == id then
      item_data.metadata = vim.tbl_extend("force", item_data.metadata, metadata)
      return true
    end
  end
  return false
end

---Get the current size of the queue
---@return number
function Queue:size()
  return self._size
end

---Check if the queue is empty
---@return boolean
function Queue:is_empty()
  return self._size == 0
end

---Clear all items from the queue
function Queue:clear()
  self._items = {}
  self._size = 0
end

---Get all items in the queue (ordered)
---@return table items Array of all items with metadata
function Queue:get_all()
  if self._size == 0 then
    return {}
  end
  
  -- Sort items according to strategy
  table.sort(self._items, function(a, b)
    return self._comparator(a, b)
  end)
  
  local items = {}
  for _, item_data in ipairs(self._items) do
    table.insert(items, {
      id = item_data.id,
      data = item_data.data,
      priority = item_data.priority,
      metadata = item_data.metadata
    })
  end
  
  return items
end

---Filter items in the queue
---@param predicate function Filter function(item, id, metadata)
---@return table filtered Array of filtered items
function Queue:filter(predicate)
  local filtered = {}
  
  for _, item_data in ipairs(self._items) do
    if predicate(item_data.data, item_data.id, item_data.metadata) then
      table.insert(filtered, {
        id = item_data.id,
        data = item_data.data,
        priority = item_data.priority,
        metadata = item_data.metadata
      })
    end
  end
  
  return filtered
end

---Find an item in the queue
---@param predicate function Search function(item, id, metadata)
---@return any|nil item, string|nil id
function Queue:find(predicate)
  for _, item_data in ipairs(self._items) do
    if predicate(item_data.data, item_data.id, item_data.metadata) then
      return item_data.data, item_data.id
    end
  end
  return nil, nil
end

---Get queue statistics
---@return table stats
function Queue:get_stats()
  local stats = {
    size = self._size,
    strategy = self._strategy,
    priorities = {},
    metadata_summary = {}
  }
  
  -- Calculate priority distribution
  local priority_counts = {}
  for _, item_data in ipairs(self._items) do
    local p = item_data.priority
    priority_counts[p] = (priority_counts[p] or 0) + 1
  end
  stats.priorities = priority_counts
  
  -- Collect metadata statistics
  if self._strategy == "size" then
    local total_size = 0
    local min_size = math.huge
    local max_size = 0
    
    for _, item_data in ipairs(self._items) do
      local size = item_data.metadata.size or 0
      total_size = total_size + size
      min_size = math.min(min_size, size)
      max_size = math.max(max_size, size)
    end
    
    stats.metadata_summary = {
      total_size = total_size,
      average_size = self._size > 0 and (total_size / self._size) or 0,
      min_size = min_size == math.huge and 0 or min_size,
      max_size = max_size
    }
  end
  
  return stats
end

---Change the queue strategy
---@param strategy string New strategy
---@param comparator? function Optional custom comparator
function Queue:set_strategy(strategy, comparator)
  self._strategy = strategy
  if comparator then
    self._comparator = comparator
  else
    self._comparator = self:_get_default_comparator()
  end
end

return Queue