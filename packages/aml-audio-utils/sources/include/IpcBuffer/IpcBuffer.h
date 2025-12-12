#ifndef __IPCBUFFER_H
#define __IPCBUFFER_H

#include <time.h>
#include <boost/interprocess/managed_shared_memory.hpp>

using namespace boost::interprocess;

class IpcBuffer
{
public:
  IpcBuffer(const char *name, size_t capacity);
  ~IpcBuffer();

  size_t size() const { return size_; }
  size_t capacity() const { return capacity_; }
  size_t write(const uint8_t *data, size_t bytes);
  size_t read(uint8_t *data, size_t bytes);
  void write_nb(const uint8_t *data, size_t bytes);
  void get_write_position(uint64_t& time, uint64_t& position);
  void reset();
  uint8_t *start_ptr();
  uint64_t wp() { return wr_position_; }
  const char *name();

  uint32_t getUnderrun() { return underrun_; }
  void incUnderrun() { underrun_++; }

  void addSilence(size_t count) { silence_inserted_ += count; }
  size_t getSilenceInserted() { return silence_inserted_; }

  void setMeta(uint64_t meta_64, uint32_t meta_32);
  void getMeta(struct timespec *ts, uint64_t *meta_64, uint32_t *meta_32);

private:
  // Note: members can be access from different process
  // only keep information which are common to all processes
  // addresses must be mapped during runtime
  size_t begin_index_, end_index_, size_, capacity_;
  managed_shared_memory::handle_t handle_;
  std::string name_;
  bool blocking_;
  interprocess_mutex mutex_;
  uint64_t wr_position_;
  uint64_t wr_time_;
  uint32_t underrun_;
  size_t silence_inserted_;
  struct timespec meta_ts_;
  uint64_t meta_64_;
  uint32_t meta_32_;
};

#endif
