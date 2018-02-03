require 'fluent/input'

module Fluent
  class PgLogicalInput < Fluent::Input
    Plugin.register_input( 'pg_logical', self)

    def initialize
      require 'pg'
      super
    end

    config_param :host, :string, :default => 'localhost'
    config_param :port, :integer, :default => 5432
    config_param :user, :string, :default => 'postgres'
    config_param :password, :string, :default => nil, :secret => true
    config_param :dbname, :string, :default => 'postgres'
    config_param :slotname, :string, :default => nil
    config_param :plugin,   :string, :default => nil
    config_param :status_interval, :integer, :default => 10
    config_param :tag, :string, :default => nil
    config_param :create_slot, :bool, :default=> false
    config_param :if_not_exists, :bool, :default => false
    def configure(conf)
      super

      # 'slot_name' parameter is mandantory.
      if (@slotname.nil?)
        raise Fluent::ConfigError, "pg-logical: missing 'slotname' parameter."
      end

      # If 'create_slot' parameter is specified, 'plugin' name is required.
      if (!@create_slot.nil? and @plugin.nil?)
        raise Fluent::ConfigError, "pg-logical: 'create_slot' parameter reuiqres to specify 'plugin' parameter."
      end
      if @tag.nil?
        raise Fluent::ConfigError, "pg-logical: missing 'tag' parameter. Please add following line into config"
      end

      log.info ":host=>#{host} :dbname=>#{dbname} :port=>#{port} :user=>#{user} :tag=>#{tag} :slotname=>#{slotname} :plugin=>#{plugin} :status_interval=>#{status_interval}"
    end

    def start
      @thread = Thread.new(&method(:run))
    end

    def shutdown
      Thread.kill(@thread)
    end

    def run
      begin
        streamLogicalLog
      rescue StandardError => e
        log.error "pg_logical: failed to execute query."
        log.error "error: #{e.message}"
        log.error e.backtrace.join("\n")
      end
    end

    # Start logical replication
    def start_streaming
      # Identify system, and get start lsn
      res = @conn.exec("IDENTIFY_SYSTEM")
      systemid = res.getvalue(0, 0)
      tli = res.getvalue(0, 1)
      xlogpos = res.getvalue(0, 2)
      dbname = res.getvalue(0, 3)

      # Start logical replication      
      strbuf = "START_REPLICATION SLOT %s LOGICAL %s" % [@slotname, xlogpos]
      @conn.exec(strbuf)
    end

    # Get a connection
    def get_connection
      begin
        return PG::connect(
                           :host => @host,
                           :port => @port,
                           :user => @user,
                           :password => @password,
                           :dbname => @dbname,
                           :replication => "database"
                         )
      rescue Exception => e
        log.warn "pg-logical: #{e}"
        sleep 5
        retry
      end
    end

    # Main routine of pg-logical plugin. Stream logical WAL.
    def streamLogicalLog
      @conn = get_connection()

      # Create replication slot if required
      create_replication_slot()

      # Start replication
      start_streaming()

      record = nil
      socket = @conn.socket_io
      time_to_abort = false
      last_status = Time.now
      loop do
        
        # Get current timestamp
        now = Time.now

        # Send feedback if necessary
        last_status = sendFeedback(now, last_status, false)

        # Get a decoded WAL decode
        record = @conn.get_copy_data(true)

        # In async mode, and no data available. We block on reading but
        # not more than the specified timeout, so that we can send a
        # response back to the client.# In asynchronou mode,
        if (record == false)
          # XXX: maybe better to use libev?
          r = select([socket], [], [], 10.0)

          if (r.nil?)
            # Got a timeout or signal. Continue the loop and either
            # deliver a status packet to the server or just go back into
            # blocking.
            next
          end

          # There is actual data on socket, consume it.
          @conn.consume_input()
          next
        end

        # record is nil means that copy is done.
        if (record.nil?)
          next
        end

        # Process a record, get extracted record
        wal = extractRecord(record)

        if (wal[:type] == 'w')	# WAL data
          #log.info "[GET w] start : #{wal[:start_lsn]}, end : #{wal[:end_lsn]}, time : #{wal[:send_time]}, data : #{wal[:data]}"
          last_status = sendFeedback(now, last_status, true)

          @router.emit(@tag, Fluent::Engine.now, wal[:data])

        elsif (wal[:type] == 'k') # Keepalive data
          #log.info "[GET k] end : #{wal[:end_lsn]}, time : #{wal[:send_time]}, reply_required : #{wal[:reply_required]}"

          if (wal[:reply_required] == 1)
              last_status = sendFeedback(now, last_status, true)
          end
        end
      end
    end

    # Return extracted WAL data into a hash map
    def extractRecord(record)
      r = record.unpack("a")
      wal = {}

      if (r[0] == 'w') # WAL data
        # -- WAL data format ------
        # 1. 'w'	: byte
        # 2. start_lsn	: uint64
        # 3. end_lsn	: uint64
        # 4. send_time	: uint64
        # 5. data
        # ------------------------
        r = record.unpack("aNNNNNNc*")

        start_lsn_h = r[1]
        start_lsn_l = r[2]
        end_lsn_h = r[3]
        end_lsn_l = r[4]
        send_time_h = r[5]
        send_time_l = r[6]
        data = r[7 .. r.size].pack("C*")

        start_lsn = (start_lsn_h << 32) + start_lsn_l
        end_lsn = (end_lsn_h << 32) + end_lsn_l
        send_time = (send_time_h << 32) + send_time_l

        wal[:type] = 'w'
        wal[:start_lsn] = start_lsn
        wal[:end_lsn] = end_lsn
        wal[:send_time] = send_time
        wal[:data] = data
      elsif (r[0] == 'k') # keepalive message
        # -- Keepalive format ------
        # 1. 'k'	: byte
        # 2. end_lsn	: uint64
        # 3. send_time	: uint64
        # 4. reply_required : byte
        # ------------------------
        r = record.unpack("aNNNNc")

        end_lsn_h = r[1]
        end_lsn_l = r[2]
        send_time_h = r[3]
        send_time_l = r[4]
        reply_required = r[5]

        end_lsn = (end_lsn_h << 32) + end_lsn_l
        send_time = (send_time_h << 32) + send_time_l

        wal[:type] = 'k'
        wal[:end_lsn] = end_lsn
        wal[:send_time] = send_time
        wal[:reply_required] = reply_required
      end

      # Update reveive lsn
      if (@recv_lsn.nil? or wal[:end_lsn] > @recv_lsn)
        @recv_lsn = wal[:end_lsn]
      end

      return wal
    end
    

    # Return the last feedback time
    def sendFeedback(now, last_status, force)

      # If the user doesn't want status to be reported the
      # upstream server, be sure to exit before doing anything
      # at all.
      if (!force and now - last_status < @status_interval)
        return last_status
      end

      # Report current status to upstream server
      if (!@recv_lsn.nil?)
        # -- Feedback format ------
        # 1. 'r'		: byte
        # 2. write_lsn	: uint64
        # 3. flush_lsn	: uint64
        # 3. apply_lsn	: uint64
        # 4. send_time	: uint64
        # 5. reply_required : byte
        # ------------------------
        feedback_msg = ['r']

        recv_lsn_h = @recv_lsn >> 32
        recv_lsn_l = @recv_lsn & 0xFFFFFFFF

        # write
        feedback_msg.push(recv_lsn_h)
        feedback_msg.push(recv_lsn_l)

        # flush
        feedback_msg.push(recv_lsn_h)
        feedback_msg.push(recv_lsn_l)

        # apply
        feedback_msg.push(0)
        feedback_msg.push(0)

        # send_time
        now_h = now.to_i >> 32
        now_l = now.to_i & 0xFFFFFFFF
        feedback_msg.push(now_h)
        feedback_msg.push(now_l)

        # Require reply
        feedback_msg.push(0)
        packed = feedback_msg.pack("aN8c")

        @conn.flush
        if (!@conn.put_copy_data(packed))
          raise "error"
        end

        # Update last_status as we've sent
        last_status = now
      end

      return last_status
    end

    # Create a replication slot
    def create_replication_slot
      begin
        strbuf = "CREATE_REPLICATION_SLOT %s LOGICAL %s" % [@slotname, @plugin]
        puts strbuf
        @conn.exec(strbuf)
      rescue PG::Error
        # If if_not_exists is set, ignore the error
        if (@if_not_exists)
          log.info "pg-logical: could not create replication slot %s" % @slotname
          return
        end

        log.error "pg-logical: could not create replication slot %s" % @slotname
      end
    end
  end
end
