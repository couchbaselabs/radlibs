module UserHelper

  # converts a hash into an array
  def array_from_hash(h)
    return h unless h.is_a? Hash

    all_numbers = h.keys.all? { |k| k.to_i.to_s == k }
    if all_numbers
      h.keys.sort_by{ |k| k.to_i }.map{ |i| array_from_hash(h[i]) }
    else
      h.each do |k, v|
        h[k] = array_from_hash(v)
      end
    end
  end


end
