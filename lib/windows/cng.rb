require_relative 'cng/constants'
require_relative 'cng/functions'
require_relative 'cng/structs'
require_relative 'cng/helper'

module Windows
  class CNG
    include Windows::CNGConstants
    include Windows::CNGFunctions
    include Windows::MiscFunctions
    include Windows::CNGStructs
    include Windows::CNGHelper

    # The version of the windows-cng library.
    VERSION = '0.0.1'

    # Creates and returns a new Windows::CNG object.
    #
    # The +algorithm+ argument specifies the type of algorithm to use for the
    # various crypto methods. The default is SHA256.
    #
    # The +implementation+ identifies the specific provider to load. This is
    # the registered alias of the cryptographic primitive provider. By default
    # this is nil.
    #
    # The flags argument can be one or more of the following values:
    #
    # * BCRYPT_ALG_HANDLE_HMAC_FLAG
    # * BCRYPT_PROV_DISPATCH
    # * BCRYPT_HASH_REUSABLE_FLAG
    #
    # See the MSDN documentation for details of what each flag does.
    #
    def initialize(algorithm = BCRYPT_SHA256_ALGORITHM, implementation = nil, flags = 0)
      @algorithm = algorithm.wincode
      @implementation = implementation ? implementation.wincode : implementation
      @flags = flags

      ptr = FFI::MemoryPointer.new(:pointer)

      status = BCryptOpenAlgorithmProvider(
        ptr,
        @algorithm,
        @implementation,
        @flags
      )

      if status != 0
        raise SystemCallError.new('BCryptOpenAlgorithmProvider', status)
      end

      @handle = ptr.read_pointer

      ObjectSpace.define_finalizer(self, self.class.finalize(@handle))
    end

    def encrypt(data)
      cbkey_object = FFI::MemoryPointer.new(:ulong)
      cbdata = FFI::MemoryPointer.new(:ulong)

      status = BCryptGetProperty(
        @handle,
        BCRYPT_OBJECT_LENGTH.wincode,
        cbkey_object,
        cbkey_object.size,
        cbdata,
        0
      )

      if status != 0
        raise SystemCallError.new('BCryptGetProperty', status)
      end

      begin
        pbkey_object = HeapAlloc(GetProcessHeap(), 0, cbkey_object.read_ulong)

        if pbkey_object.null?
          raise SystemCallError.new('HeapAlloc', FFI.errno)
        end
      ensure
        if pbkey_object && !pbkey_object.null?
          HeapFree(GetProcessHeap(), 0, pbkey_object)
        end
      end
    end

    # Returns a hash of +data+ using the algorithm used in the constructor.
    #
    def hash(data)
      cbhash_object = FFI::MemoryPointer.new(:ulong)
      cbdata = FFI::MemoryPointer.new(:ulong)

      status = BCryptGetProperty(
        @handle,
        BCRYPT_OBJECT_LENGTH.wincode,
        cbhash_object,
        cbhash_object.size,
        cbdata,
        0
      )

      if status != 0
        raise SystemCallError.new('BCryptGetProperty', status)
      end

      begin
        pbhash_object = HeapAlloc(GetProcessHeap(), 0, cbhash_object.read_ulong)

        if pbhash_object.null?
          raise SystemCallError.new('HeapAlloc', FFI.errno)
        end

        cbhash = FFI::MemoryPointer.new(:ulong)
        cbdata.clear

        status = BCryptGetProperty(
          @handle,
          BCRYPT_HASH_LENGTH.wincode,
          cbhash,
          cbhash.size,
          cbdata,
          0
        )

        if status != 0
          raise SystemCallError.new('BCryptGetProperty', status)
        end

        cbhash = cbhash.read_ulong
        pbhash = HeapAlloc(GetProcessHeap(), 0, cbhash)

        if pbhash.null?
          raise SystemCallError.new('HeapAlloc', FFI.errno)
        end

        ptr = FFI::MemoryPointer.new(:pointer)

        status = BCryptCreateHash(
          @handle,
          ptr,
          pbhash_object,
          cbhash_object.read_ulong,
          nil,
          0,
          0
        )

        if status != 0
          raise SystemCallError.new('BCryptCreateHash', status)
        end

        hhash = ptr.read_pointer

        status = BCryptHashData(hhash, data, data.size, 0)

        if status != 0
          raise SystemCallError.new('BCryptHashData', status)
        end

        status = BCryptFinishHash(hhash, pbhash, cbhash, 0)

        if status != 0
          raise SystemCallError.new('BCryptFinishHash', status)
        end

        pbhash.read_bytes(cbhash)
      ensure
        if pbhash_object && !pbhash_object.null?
          HeapFree(GetProcessHeap(), 0, pbhash_object)
        end

        if pbhash && !pbhash.null?
          HeapFree(GetProcessHeap(), 0, pbhash)
        end
      end
    end

    # Closes the windows-cng object. This is not explicitly required, since
    # it will automatically be called once your object goes out of scope, but
    # it is good form.
    #
    def close
      status = BCryptCloseAlgorithmProvider(@handle, 0)

      if status != 0
        raise SystemCallError.new('BCryptCloseAlgorithmProvider', status)
      end
    end

    private

    # Automatically close crypto object when it goes out of scope.
    #
    def self.finalize(handle)
      proc{ BCryptCloseAlgorithmProvider(handle, 0) }
    end
  end
end
