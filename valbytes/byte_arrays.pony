use "collections"

class val ByteArrays is (ValBytes & Hashable)
  let _left: ValBytes
  let _right: ValBytes
  let _left_size: USize

  new val create(
    left: ValBytes = recover val Array[U8](0) end,
    right: ValBytes = recover val Array[U8](0) end
  ) =>
    _left = left
    _right = right
    _left_size = _left.size()

  fun size(): USize => _left.size() + _right.size()

  fun apply(i: USize): U8 ? =>
    if i < _left_size then
      _left(i)?
    else
      _right(i - _left_size)?
    end

  fun values(): Iterator[U8] =>
    object is Iterator[U8]
      let _left_values:  Iterator[U8] = _left.values()
      let _right_values:  Iterator[U8] = _right.values()
      fun ref next(): U8 ? =>
        try
          _left_values.next()?
        else
          _right_values.next()?
        end
      fun ref has_next(): Bool =>
        _left_values.has_next() or _right_values.has_next()
    end

  fun drop(amount: USize): ByteArrays =>
    if amount < _left_size then
      ByteArrays(_left.trim(amount, -1), _right)
    else
      let right_skip = amount - _left_size
      ByteArrays(_right.trim(right_skip, -1))
    end

  fun take(amount: USize): ByteArrays =>
    if amount < _left_size then
      ByteArrays(_left.trim(0, amount))
    else
      ByteArrays(_left, _right.trim(0, amount - _left_size))
    end

  fun trim(from: USize = 0 , to: USize = -1): Array[U8] val =>
    """
    In best case no additional allocation, yay!
    """
    if to < _left_size then
      _left.trim(from, to)
    elseif from >= _left_size then
      _right.trim(from - _left_size, to - _left_size)
    else
      // expensive case, we need to allocate a new array :(
      let last = size().min(to)
      let offset = last.min(from)
      let size' = last - offset
      recover val
        let res = Array[U8](size')
        let left_bytes_to_copy = _left_size - offset
        _left.copy_to(res, offset, 0, left_bytes_to_copy)
        _right.copy_to(res, 0, left_bytes_to_copy, size' - left_bytes_to_copy)
        res
      end
    end

  fun copy_to(
    dst: Array[this->U8!],
    src_idx: USize,
    dst_idx: USize,
    len: USize) =>
    let last = (src_idx + len).min(size())
    if last < _left_size then
      _left.copy_to(dst, src_idx, dst_idx, len)
    elseif src_idx >= _left_size then
      _right.copy_to(dst, src_idx - _left_size, dst_idx, len)
    else
      // dang, interval stretches from _left to _right
      let offset = last.min(src_idx)
      let left_bytes_to_copy = _left_size - offset
      _left.copy_to(dst, offset, dst_idx, left_bytes_to_copy)
      _right.copy_to(dst, 0, dst_idx + left_bytes_to_copy, len - left_bytes_to_copy)
    end

  fun string(from: USize = 0, to: USize = -1): String val =>
    """
    diverges from usual Stringable.string in that
    it can be used to get a substring of the whole ByteArrays instance
    and that the result is val and in best case no additional allocation was necessary.
    """
    String.from_array(trim(from, to))

  fun array(): Array[U8] val => trim(0, size() - 1)

  fun val add(other: (ValBytes | String)): ByteArrays =>
    """
    Enable convenient concatenation via  `+` operator:

    ```pony
    ByteArrays("a") + "b" + [as U8: 'c']
    ```
    """
    let that: ValBytes =
      match other
      | let t: String => t.array()
      | let vb: ValBytes => vb
      end
    if _right.size() == 0 then
      if _left_size == 0 then
        ByteArrays(that)
      else
        ByteArrays(_left, that)
      end
    else
      ByteArrays(this, that)
    end

  fun find(sub: ReadSeq[U8], start: USize = 0, stop: USize = -1): (Bool, USize) =>
    """
    Try to find `sub` in this ByteArrays.

    If found, returns a tuple with the first element being `true` and the second element
    being the starting index of `sub` in this.

    ```pony
    let ba = ByteArrays + "abc" + "def"
    match ba.find("cd")
    | (true, let cd_index: USize) => "found"
    | (false, _) => "not found"
    end
    ```
    """
    var i = start
    let this_size = size()
    let max: USize = this_size.min(stop)
    let sub_size = sub.size()

    try
      while i < max do
        var j = USize(0)
        let same: Bool =
          while (j < sub_size) do
            if ((i + j) >= max) or (apply(i + j)? != sub.apply(j)?) then
              break false
            end
            j = j + 1
            true
          else
            false
          end
        if same then
          return (true, i)
        end
        i = i + 1
      end
    else
      (false, USize(0))
    end
    (false, USize(0))

  fun skip_while(f: {(U8): Bool?} val, start: USize): USize =>
    """
    returns the first index for which f returns false,
    USize.max_value() if it never returns true
    """
    var i = start
    var this_size = size()
    try
      while i < this_size do
        let c = apply(i)?
        if not f(c)? then
          return i
        end
        i = i + 1
      end
      USize.max_value()
    else
      USize.max_value()
    end

  fun skip(skip_chars: ReadSeq[U8], start: USize = 0): USize =>
    """
    return the first index in this that doesnt contain any element of `skip_chars`.

    If we reach the end while skipping USize.max_value() is returned.
    """
    var i = start
    let this_size = size()
    let skip_size = skip_chars.size()
    try
      while i < this_size do
        let c = apply(i)?
        var contained: Bool = false

        var j = USize(0)
        while j < skip_size do
          if c == skip_chars(j)? then
            contained = true
          end
          j = j + 1
        end
        if not contained then
          return i
        end
        i = i + 1
      end
      USize.max_value()
    else
      USize.max_value()
    end


  fun hash(): USize =>
    ifdef ilp32 then
      _HalfSipHash24[ByteArrays box](this).usize()
    else
      _SipHash24[ByteArrays box](this).usize()
    end

  fun read_u8[T: U8](offset: USize): U8 ? => this(offset)?

  fun read_u16[T:U8](offset: USize): U16 ? =>
    let end_offset = offset + U16(0).bytewidth()
    if end_offset <= _left_size then
      // we can conveniently use left's implementation of read_u8
      _left.read_u16(offset)?
    elseif offset > _left_size then
      // we can conveniently use right's implementation of read_u8
      _right.read_u16(offset - _left_size)?
    else
      // we need to fiddle with those fucking bytes
      this(offset)?.u16() or
      (this(offset + 1)?.u16() << 8)
    end

  fun read_u32[T:U8](offset: USize): U32 ? =>
    let end_offset = offset + U32(0).bytewidth()
    if end_offset <= _left_size then
      // we can conveniently use left's implementation of read_u8
      _left.read_u32(offset)?
    elseif offset > _left_size then
      // we can conveniently use right's implementation of read_u8
      _right.read_u32(offset - _left_size)?
    else
      // we need to fiddle with those fucking bytes
      this(offset)?.u32() or
      (this(offset + 1)?.u32() << 8) or
      (this(offset + 2)?.u32() << 16) or
      (this(offset + 3)?.u32() << 24)
    end

  fun read_u64[T:U8](offset: USize): U64 ? =>
    let end_offset = offset + U64(0).bytewidth()
    if end_offset <= _left_size then
      // we can conveniently use left's implementation of read_u8
      _left.read_u64(offset)?
    elseif offset > _left_size then
      // we can conveniently use right's implementation of read_u8
      _right.read_u64(offset - _left_size)?
    else
      // we need to fiddle with those fucking bytes
      this(offset)?.u64() or
      (this(offset + 1)?.u64() << 8) or
      (this(offset + 2)?.u64() << 16) or
      (this(offset + 3)?.u64() << 24) or
      (this(offset + 4)?.u64() << 32) or
      (this(offset + 5)?.u64() << 40) or
      (this(offset + 6)?.u64() << 48) or
      (this(offset + 7)?.u64() << 56)
    end

  fun read_u128[T:U8](offset: USize): U128 ? =>
    let end_offset = offset + U128(0).bytewidth()
    if end_offset <= _left_size then
      // we can conveniently use left's implementation of read_u8
      _left.read_u128(offset)?
    elseif offset > _left_size then
      // we can conveniently use right's implementation of read_u8
      _right.read_u128(offset - _left_size)?
    else
      // we need to fiddle with those fucking bytes
      this(offset)?.u128() or
      (this(offset + 1)?.u128() << 8) or
      (this(offset + 2)?.u128() << 16) or
      (this(offset + 3)?.u128() << 24) or
      (this(offset + 4)?.u128() << 32) or
      (this(offset + 5)?.u128() << 40) or
      (this(offset + 6)?.u128() << 48) or
      (this(offset + 7)?.u128() << 56) or
      (this(offset + 8)?.u128() << 64) or
      (this(offset + 9)?.u128() << 72) or
      (this(offset + 10)?.u128() << 80) or
      (this(offset + 11)?.u128() << 88) or
      (this(offset + 12)?.u128() << 96) or
      (this(offset + 13)?.u128() << 104) or
      (this(offset + 14)?.u128() << 112) or
      (this(offset + 15)?.u128() << 120)
    end




